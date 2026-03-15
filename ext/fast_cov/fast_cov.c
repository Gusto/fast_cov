#include <ruby.h>
#include <ruby/version.h>
#include <ruby/debug.h>

#include <stdbool.h>

#include "fast_cov.h"

// FastCov: native C extension for fast Ruby code coverage tracking.
//
// Tracks which source files are executed during a test run by hooking into
// Ruby VM events. Designed for test impact analysis.

// threads: true = multi-threaded (global hook), false = single-threaded (per-thread hook)

// Forward declarations
static VALUE fast_cov_stop(VALUE self);
static VALUE fast_cov_yield_block(VALUE _arg);

// ---- Data structure -----------------------------------------------------

struct fast_cov_data {
  VALUE impacted_files;

  char *root;
  long root_len;

  char **ignored_paths;
  long *ignored_path_lens;
  long ignored_paths_count;

  uintptr_t last_filename_ptr;

  bool threads;
  bool started;
  VALUE th_covered;
};

// ---- GC callbacks -------------------------------------------------------
//
// We use rb_gc_mark (non-movable, pins objects) instead of rb_gc_mark_movable.
// On Ruby 3.4, rb_gc_mark_movable + dcompact causes T_NONE crashes during
// compaction. Pinning avoids this with negligible performance impact.

static void fast_cov_mark(void *ptr) {
  struct fast_cov_data *data = ptr;
  rb_gc_mark(data->impacted_files);
  rb_gc_mark(data->th_covered);
}

static void fast_cov_free(void *ptr) {
  struct fast_cov_data *data = ptr;
  long i;
  if (data->root) xfree(data->root);
  if (data->ignored_paths) {
    for (i = 0; i < data->ignored_paths_count; i++) {
      xfree(data->ignored_paths[i]);
    }
    xfree(data->ignored_paths);
  }
  if (data->ignored_path_lens) xfree(data->ignored_path_lens);
  xfree(data);
}

static const rb_data_type_t fast_cov_data_type = {
    .wrap_struct_name = "fast_cov",
    .function = {.dmark = fast_cov_mark,
                 .dfree = fast_cov_free,
                 .dsize = NULL},
    .flags = 0};

// ---- Allocator ----------------------------------------------------------

static VALUE fast_cov_allocate(VALUE klass) {
  struct fast_cov_data *data;
  VALUE obj = TypedData_Make_Struct(klass, struct fast_cov_data,
                                   &fast_cov_data_type, data);

  // Initialize all VALUE fields to Qnil before any allocation that could
  // trigger GC. TypedData_Make_Struct zeroes memory (via calloc), but 0 is
  // Qfalse, not Qnil — and marking Qfalse can confuse Ruby 3.4's GC.
  data->impacted_files = Qnil;
  data->th_covered = Qnil;

  data->impacted_files = rb_hash_new();
  data->root = NULL;
  data->root_len = 0;
  data->ignored_paths = NULL;
  data->ignored_path_lens = NULL;
  data->ignored_paths_count = 0;
  data->last_filename_ptr = 0;
  data->threads = true;
  data->started = false;

  return obj;
}

// ---- Internal helpers ---------------------------------------------------

static bool record_impacted_file(struct fast_cov_data *data, VALUE filename) {
  if (!fast_cov_is_path_included(RSTRING_PTR(filename), data->root,
                                 data->root_len, data->ignored_paths,
                                 data->ignored_path_lens,
                                 data->ignored_paths_count)) {
    return false;
  }

  rb_hash_aset(data->impacted_files, filename, Qtrue);
  return true;
}

static VALUE fast_cov_yield_block(VALUE _arg) { return rb_yield(Qnil); }

// ---- Line event callback ------------------------------------------------

static void on_line_event(rb_event_flag_t event, VALUE self_data, VALUE self,
                          ID id, VALUE klass) {
  struct fast_cov_data *data;
  TypedData_Get_Struct(self_data, struct fast_cov_data, &fast_cov_data_type,
                       data);

  const char *c_filename = rb_sourcefile();

  uintptr_t current_filename_ptr = (uintptr_t)c_filename;
  if (data->last_filename_ptr == current_filename_ptr) {
    return;
  }
  data->last_filename_ptr = current_filename_ptr;

  VALUE top_frame;
  if (rb_profile_frames(0, 1, &top_frame, NULL) != 1) {
    return;
  }

  VALUE filename = rb_profile_frame_path(top_frame);
  if (filename == Qnil) {
    return;
  }

  record_impacted_file(data, filename);
}

// ---- Utils module methods (FastCov::Utils) ------------------------------

// Utils.path_within?(path, directory) -> true/false
// Check if path is within directory, correctly handling:
// - Trailing slashes on directory
// - Sibling directories with longer names (e.g., /a/b/c vs /a/b/cd)
static VALUE utils_path_within(VALUE self, VALUE path, VALUE directory) {
  Check_Type(path, T_STRING);
  Check_Type(directory, T_STRING);

  // Freeze strings to prevent GC compaction from moving them
  rb_str_freeze(path);
  rb_str_freeze(directory);

  bool result = fast_cov_is_within_root(
      RSTRING_PTR(path), RSTRING_LEN(path),
      RSTRING_PTR(directory), RSTRING_LEN(directory));

  return result ? Qtrue : Qfalse;
}

// Utils.relativize_paths(set, root) -> set
// Mutates set in place: converts absolute paths to relative paths from root.
// Paths not within root are left unchanged.
static VALUE utils_relativize_paths(VALUE self, VALUE set, VALUE root) {
  Check_Type(root, T_STRING);

  // Freeze root to prevent GC from moving it during compaction
  rb_str_freeze(root);

  const char *root_ptr = RSTRING_PTR(root);
  long root_len = RSTRING_LEN(root);

  // Normalize: strip trailing slash for offset calculation
  long effective_root_len = root_len;
  if (effective_root_len > 0 && root_ptr[effective_root_len - 1] == '/') {
    effective_root_len--;
  }

  // Collect paths to transform (can't modify set while iterating)
  VALUE paths = rb_funcall(set, rb_intern("to_a"), 0);
  long num_paths = RARRAY_LEN(paths);

  for (long i = 0; i < num_paths; i++) {
    VALUE abs_path = rb_ary_entry(paths, i);
    if (!RB_TYPE_P(abs_path, T_STRING)) continue;

    // Freeze to prevent GC moving it
    rb_str_freeze(abs_path);

    const char *path_ptr = RSTRING_PTR(abs_path);
    long path_len = RSTRING_LEN(abs_path);

    // Use proper within_root check
    if (!fast_cov_is_within_root(path_ptr, path_len, root_ptr, root_len)) {
      continue;
    }

    // Calculate offset (skip root + separator)
    long offset = effective_root_len;
    if (offset < path_len && path_ptr[offset] == '/') offset++;

    // Create relative path
    VALUE rel_path = rb_str_substr(abs_path, offset, path_len - offset);

    // Delete old path, add new path
    rb_funcall(set, rb_intern("delete"), 1, abs_path);
    rb_funcall(set, rb_intern("add"), 1, rel_path);
  }

  RB_GC_GUARD(paths);
  return set;
}

// ---- Ruby instance methods ----------------------------------------------

static VALUE fast_cov_initialize(int argc, VALUE *argv, VALUE self) {
  VALUE opt;
  rb_scan_args(argc, argv, "01", &opt);
  if (NIL_P(opt)) opt = rb_hash_new();

  // root: defaults to Dir.pwd
  VALUE rb_root = rb_hash_lookup(opt, ID2SYM(rb_intern("root")));
  if (!RTEST(rb_root)) {
    rb_root = rb_funcall(rb_cDir, rb_intern("pwd"), 0);
  }
  Check_Type(rb_root, T_STRING);

  // ignored_paths: optional array, [] if not provided
  VALUE rb_ignored_paths =
      rb_hash_lookup(opt, ID2SYM(rb_intern("ignored_paths")));
  if (!NIL_P(rb_ignored_paths)) {
    Check_Type(rb_ignored_paths, T_ARRAY);
  }

  // threads: true (multi) or false (single), defaults to true
  VALUE rb_threads = rb_hash_lookup(opt, ID2SYM(rb_intern("threads")));
  bool threads = (rb_threads != Qfalse);

  struct fast_cov_data *data;
  TypedData_Get_Struct(self, struct fast_cov_data, &fast_cov_data_type, data);

  data->threads = threads;
  if (data->root) xfree(data->root);
  data->root_len = RSTRING_LEN(rb_root);
  data->root =
      fast_cov_ruby_strndup(RSTRING_PTR(rb_root), data->root_len);

  if (data->ignored_paths) {
    long i;
    for (i = 0; i < data->ignored_paths_count; i++) {
      xfree(data->ignored_paths[i]);
    }
    xfree(data->ignored_paths);
    data->ignored_paths = NULL;
  }
  if (data->ignored_path_lens) {
    xfree(data->ignored_path_lens);
    data->ignored_path_lens = NULL;
  }
  data->ignored_paths_count = 0;

  if (!NIL_P(rb_ignored_paths) && RARRAY_LEN(rb_ignored_paths) > 0) {
    long i;
    long ignored_paths_count = RARRAY_LEN(rb_ignored_paths);

    for (i = 0; i < ignored_paths_count; i++) {
      Check_Type(rb_ary_entry(rb_ignored_paths, i), T_STRING);
    }

    data->ignored_paths_count = ignored_paths_count;
    data->ignored_paths = xmalloc(sizeof(char *) * data->ignored_paths_count);
    data->ignored_path_lens = xmalloc(sizeof(long) * data->ignored_paths_count);

    for (i = 0; i < data->ignored_paths_count; i++) {
      VALUE rb_ignored_path = rb_ary_entry(rb_ignored_paths, i);

      data->ignored_path_lens[i] = RSTRING_LEN(rb_ignored_path);
      data->ignored_paths[i] =
          fast_cov_ruby_strndup(RSTRING_PTR(rb_ignored_path),
                                data->ignored_path_lens[i]);
    }
  }

  return Qnil;
}

static VALUE fast_cov_start(VALUE self) {
  struct fast_cov_data *data;
  TypedData_Get_Struct(self, struct fast_cov_data, &fast_cov_data_type, data);

  if (data->root_len == 0) {
    rb_raise(rb_eRuntimeError, "root is required");
  }

  if (data->started) {
    if (rb_block_given_p()) {
      rb_raise(rb_eRuntimeError, "Coverage is already started");
    }
    return self;
  }

  if (!data->threads) {
    VALUE thval = rb_thread_current();
    rb_thread_add_event_hook(thval, on_line_event, RUBY_EVENT_LINE, self);
    data->th_covered = thval;
  } else {
    rb_add_event_hook(on_line_event, RUBY_EVENT_LINE, self);
  }
  data->started = true;

  // Block form: start { ... } runs the block then returns stop result
  if (rb_block_given_p()) {
    int exception_state = 0;
    rb_protect(fast_cov_yield_block, Qnil, &exception_state);
    VALUE result = fast_cov_stop(self);
    if (exception_state != 0) {
      rb_jump_tag(exception_state);
    }
    return result;
  }

  return self;
}

static VALUE fast_cov_stop(VALUE self) {
  struct fast_cov_data *data;
  TypedData_Get_Struct(self, struct fast_cov_data, &fast_cov_data_type, data);

  if (!data->started) {
    return rb_hash_new();
  }

  if (!data->threads) {
    VALUE thval = rb_thread_current();
    if (thval != data->th_covered) {
      rb_raise(rb_eRuntimeError, "Coverage was not started by this thread");
    }
    rb_thread_remove_event_hook(data->th_covered, on_line_event);
    data->th_covered = Qnil;
  } else {
    rb_remove_event_hook(on_line_event);
  }

  VALUE res = data->impacted_files;

  data->impacted_files = rb_hash_new();
  data->last_filename_ptr = 0;
  data->started = false;

  return res;
}

// ---- Init ---------------------------------------------------------------

void Init_fast_cov(void) {
  VALUE mFastCov = rb_define_module("FastCov");

  VALUE cCoverage = rb_define_class_under(mFastCov, "Coverage", rb_cObject);

  rb_define_alloc_func(cCoverage, fast_cov_allocate);
  rb_define_method(cCoverage, "initialize", fast_cov_initialize, -1);
  rb_define_method(cCoverage, "start", fast_cov_start, 0);
  rb_define_method(cCoverage, "stop", fast_cov_stop, 0);

  // FastCov::Utils module (C-defined methods)
  VALUE mUtils = rb_define_module_under(mFastCov, "Utils");
  rb_define_module_function(mUtils, "path_within?", utils_path_within, 2);
  rb_define_module_function(mUtils, "relativize_paths", utils_relativize_paths, 2);
}
