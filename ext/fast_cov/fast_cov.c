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

// Seen-set sizing. Power-of-two capacities so lookups mask instead of modulo.
#define SEEN_INITIAL_CAPACITY 256
// Grow at 3/4 load. Linear probing degrades sharply past that, and a full
// table would make the insert probe loop spin forever.
#define SEEN_LOAD_NUMERATOR 3
#define SEEN_LOAD_DENOMINATOR 4

// ---- Data structure -----------------------------------------------------

struct fast_cov_data {
  VALUE impacted_files;

  char *root;
  long root_len;

  char **ignored_paths;
  long *ignored_path_lens;
  long ignored_paths_count;

  // Two-level cache over source file identity, both keyed on the pointer
  // rb_sourcefile() returns (stable per file, so comparing it is one
  // integer compare instead of a string compare):
  //
  //   last_filename_ptr - single slot, hits while execution stays in one file
  //   seen_*            - open-addressed set of every file seen this session,
  //                       so alternating between files stays on the fast path
  uintptr_t last_filename_ptr;

  uintptr_t *seen_ptrs;
  VALUE *seen_paths;
  long seen_capacity;
  long seen_count;

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
  long i;

  rb_gc_mark(data->impacted_files);
  rb_gc_mark(data->th_covered);

  // Pinning the path strings is what makes the pointer cache sound: it keeps
  // each rb_sourcefile() pointer alive and at a fixed address for the whole
  // session. Without it a freed string's address could be reused by another
  // file, which would read as a cache hit and silently drop that file.
  for (i = 0; i < data->seen_capacity; i++) {
    if (data->seen_ptrs[i]) rb_gc_mark(data->seen_paths[i]);
  }
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
  if (data->seen_ptrs) xfree(data->seen_ptrs);
  if (data->seen_paths) xfree(data->seen_paths);
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

  // Keep seen_capacity at 0 until both arrays are installed: xcalloc can
  // trigger GC, and fast_cov_mark walks seen_capacity entries.
  data->seen_capacity = 0;
  data->seen_count = 0;
  data->seen_ptrs = NULL;
  data->seen_paths = NULL;

  uintptr_t *seen_ptrs = xcalloc(SEEN_INITIAL_CAPACITY, sizeof(uintptr_t));
  VALUE *seen_paths = xcalloc(SEEN_INITIAL_CAPACITY, sizeof(VALUE));
  data->seen_ptrs = seen_ptrs;
  data->seen_paths = seen_paths;
  data->seen_capacity = SEEN_INITIAL_CAPACITY;

  return obj;
}

// ---- Seen-set -----------------------------------------------------------
//
// Open-addressed set of the rb_sourcefile() pointers seen this session, with
// the corresponding path string stored alongside so it can be pinned. Linear
// probing keeps lookups in one cache line for the common case.

// The low bits of a pointer carry little entropy (allocations are aligned),
// so shift them off before masking.
static inline long seen_slot(uintptr_t filename_ptr, long capacity) {
  return (long)((filename_ptr >> 3) & (uintptr_t)(capacity - 1));
}

static inline bool seen_include(const struct fast_cov_data *data,
                                uintptr_t filename_ptr) {
  long slot = seen_slot(filename_ptr, data->seen_capacity);

  while (data->seen_ptrs[slot]) {
    if (data->seen_ptrs[slot] == filename_ptr) return true;
    slot = (slot + 1) & (data->seen_capacity - 1);
  }

  return false;
}

static void seen_grow(struct fast_cov_data *data) {
  uintptr_t *old_ptrs = data->seen_ptrs;
  VALUE *old_paths = data->seen_paths;
  long old_capacity = data->seen_capacity;
  long new_capacity = old_capacity * 2;
  long i;

  // Allocate both arrays before installing either. GC can run inside xcalloc,
  // and fast_cov_mark must keep seeing a consistent capacity/arrays triple.
  uintptr_t *new_ptrs = xcalloc(new_capacity, sizeof(uintptr_t));
  VALUE *new_paths = xcalloc(new_capacity, sizeof(VALUE));

  for (i = 0; i < old_capacity; i++) {
    uintptr_t filename_ptr = old_ptrs[i];
    if (!filename_ptr) continue;

    long slot = seen_slot(filename_ptr, new_capacity);
    while (new_ptrs[slot]) {
      slot = (slot + 1) & (new_capacity - 1);
    }
    new_ptrs[slot] = filename_ptr;
    new_paths[slot] = old_paths[i];
  }

  // Install, then free: the struct must never point at freed arrays, since a
  // GC between the two would mark through them.
  data->seen_ptrs = new_ptrs;
  data->seen_paths = new_paths;
  data->seen_capacity = new_capacity;

  xfree(old_ptrs);
  xfree(old_paths);
}

static void seen_add(struct fast_cov_data *data, uintptr_t filename_ptr,
                     VALUE path) {
  if (data->seen_count + 1 >
      data->seen_capacity * SEEN_LOAD_NUMERATOR / SEEN_LOAD_DENOMINATOR) {
    seen_grow(data);
  }

  long slot = seen_slot(filename_ptr, data->seen_capacity);
  while (data->seen_ptrs[slot]) {
    if (data->seen_ptrs[slot] == filename_ptr) return;
    slot = (slot + 1) & (data->seen_capacity - 1);
  }

  data->seen_ptrs[slot] = filename_ptr;
  data->seen_paths[slot] = path;
  data->seen_count++;
}

static void seen_clear(struct fast_cov_data *data) {
  MEMZERO(data->seen_ptrs, uintptr_t, data->seen_capacity);
  MEMZERO(data->seen_paths, VALUE, data->seen_capacity);
  data->seen_count = 0;
}

// ---- Internal helpers ---------------------------------------------------

static bool record_impacted_file(struct fast_cov_data *data, VALUE filename) {
  // RSTRING_LEN is O(1); passing it avoids re-scanning the path with strlen.
  if (!fast_cov_is_path_included(RSTRING_PTR(filename), RSTRING_LEN(filename),
                                 data->root, data->root_len,
                                 data->ignored_paths, data->ignored_path_lens,
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

  // Execution alternates between files constantly (a method in one file
  // calling into another), so the single slot above misses often. Anything
  // already seen this session is resolved here without touching the VM.
  if (seen_include(data, current_filename_ptr)) {
    return;
  }

  VALUE top_frame;
  if (rb_profile_frames(0, 1, &top_frame, NULL) != 1) {
    return;
  }

  VALUE filename = rb_profile_frame_path(top_frame);
  if (filename == Qnil) {
    return;
  }

  // Only cache pointers we hold a path string for — the pin in fast_cov_mark
  // is what keeps the pointer valid and unambiguous.
  seen_add(data, current_filename_ptr, filename);
  record_impacted_file(data, filename);
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

  char *root = fast_cov_ruby_strndup(RSTRING_PTR(rb_root), RSTRING_LEN(rb_root));

  data->threads = threads;
  if (data->root) xfree(data->root);
  data->root = root;
  data->root_len = RSTRING_LEN(rb_root);

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
    data->ignored_paths = xcalloc(data->ignored_paths_count, sizeof(char *));
    data->ignored_path_lens = xcalloc(data->ignored_paths_count, sizeof(long));

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
    // Match on the registering object, not just the callback. The plain
    // rb_*_remove_event_hook variants match by function pointer alone, so
    // stopping one Coverage instance would tear down the hooks belonging to
    // every other live instance — silently, since those instances stay
    // `started` and simply stop recording.
    rb_thread_remove_event_hook_with_data(data->th_covered, on_line_event, self);
    data->th_covered = Qnil;
  } else {
    rb_remove_event_hook_with_data(on_line_event, self);
  }

  VALUE res = data->impacted_files;

  data->impacted_files = rb_hash_new();
  data->last_filename_ptr = 0;
  seen_clear(data);
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

}
