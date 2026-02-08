#include <ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>

#include <stdbool.h>

#include "fast_cov.h"

// FastCov: native C extension for fast Ruby code coverage tracking.
//
// Tracks which source files are executed during a test run by hooking into
// Ruby VM events. Designed for test impact analysis.

#define PROFILE_FRAMES_BUFFER_SIZE 1
#define MAX_CONST_RESOLUTION_ROUNDS 10

// threads: true = multi-threaded (global hook), false = single-threaded (per-thread hook)

// Constant resolution via Ruby helper (FastCov::ConstantExtractor)
static VALUE cConstantExtractor;
static ID id_extract;
static ID id_keys;

// Cache infrastructure
VALUE fast_cov_cache_hash; // process-level cache (non-static for access from utils)
static VALUE cDigest;             // Digest::MD5
static ID id_file;
static ID id_hexdigest;
static ID id_clear;
static ID id_merge_bang;

// Forward declarations
static void on_newobj_event(VALUE tracepoint_data, void *data);
static VALUE fast_cov_stop(VALUE self);

static int mark_key_for_gc_i(st_data_t key, st_data_t _value,
                              st_data_t _data) {
  rb_gc_mark((VALUE)key);
  return ST_CONTINUE;
}

// ---- Data structure -----------------------------------------------------

struct fast_cov_data {
  VALUE impacted_files;

  char *root;
  long root_len;

  char *ignored_path;
  long ignored_path_len;

  uintptr_t last_filename_ptr;

  bool threads;
  bool constant_references;
  bool allocations;
  VALUE th_covered;

  VALUE object_allocation_tracepoint;
  st_table *klasses_table;
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
  rb_gc_mark(data->object_allocation_tracepoint);

  if (data->klasses_table != NULL) {
    st_foreach(data->klasses_table, mark_key_for_gc_i, 0);
  }
}

static void fast_cov_free(void *ptr) {
  struct fast_cov_data *data = ptr;
  if (data->root) xfree(data->root);
  if (data->ignored_path) xfree(data->ignored_path);
  if (data->klasses_table) st_free_table(data->klasses_table);
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
  data->object_allocation_tracepoint = Qnil;
  data->klasses_table = NULL;

  data->impacted_files = rb_hash_new();
  data->root = NULL;
  data->root_len = 0;
  data->ignored_path = NULL;
  data->ignored_path_len = 0;
  data->last_filename_ptr = 0;
  data->threads = true;
  data->constant_references = true;
  data->allocations = true;
  data->klasses_table = st_init_numtable();

  return obj;
}

// ---- Internal helpers ---------------------------------------------------

static bool record_impacted_file(struct fast_cov_data *data, VALUE filename) {
  if (!fast_cov_is_path_included(RSTRING_PTR(filename), data->root,
                                 data->root_len, data->ignored_path,
                                 data->ignored_path_len)) {
    return false;
  }

  rb_hash_aset(data->impacted_files, filename, Qtrue);
  return true;
}

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
  int captured_frames =
      rb_profile_frames(0, PROFILE_FRAMES_BUFFER_SIZE, &top_frame, NULL);

  if (captured_frames != PROFILE_FRAMES_BUFFER_SIZE) {
    return;
  }

  VALUE filename = rb_profile_frame_path(top_frame);
  if (filename == Qnil) {
    return;
  }

  record_impacted_file(data, filename);
}

// ---- Allocation tracing helpers -----------------------------------------

static VALUE safely_get_class_name(VALUE klass) {
  return fast_cov_rescue_nil(rb_class_name, klass);
}

static VALUE safely_get_mod_ancestors(VALUE klass) {
  return fast_cov_rescue_nil(rb_mod_ancestors, klass);
}

static bool record_impacted_klass(struct fast_cov_data *data, VALUE klass) {
  VALUE klass_name = safely_get_class_name(klass);
  if (klass_name == Qnil) {
    return false;
  }

  VALUE filename = fast_cov_resolve_const_to_file(klass_name);
  if (filename == Qnil) {
    return false;
  }

  return record_impacted_file(data, filename);
}

static int each_instantiated_klass(st_data_t key, st_data_t _value,
                                   st_data_t cb_data) {
  VALUE klass = (VALUE)key;
  struct fast_cov_data *data = (struct fast_cov_data *)cb_data;

  VALUE ancestors = safely_get_mod_ancestors(klass);
  if (ancestors == Qnil || !RB_TYPE_P(ancestors, T_ARRAY)) {
    return ST_CONTINUE;
  }

  long len = RARRAY_LEN(ancestors);
  for (long i = 0; i < len; i++) {
    VALUE mod = rb_ary_entry(ancestors, i);
    if (mod == Qnil) {
      continue;
    }
    record_impacted_klass(data, mod);
  }

  return ST_CONTINUE;
}

// ---- Newobj event callback ----------------------------------------------

static void on_newobj_event(VALUE tracepoint_data, void *raw_data) {
  rb_trace_arg_t *tracearg = rb_tracearg_from_tracepoint(tracepoint_data);
  VALUE new_object = rb_tracearg_object(tracearg);

  enum ruby_value_type type = rb_type(new_object);
  if (type != RUBY_T_OBJECT && type != RUBY_T_STRUCT) {
    return;
  }

  VALUE klass = rb_class_of(new_object);
  if (klass == Qnil || klass == 0) {
    return;
  }
  if (rb_mod_name(klass) == Qnil) {
    return;
  }

  struct fast_cov_data *data = (struct fast_cov_data *)raw_data;
  st_insert(data->klasses_table, (st_data_t)klass, 1);
}

// ---- Constant reference resolution (cached) -----------------------------

// Computes MD5 hexdigest of a file's contents.
static VALUE compute_file_digest_body(VALUE filename) {
  VALUE digest_obj = rb_funcall(cDigest, id_file, 1, filename);
  return rb_funcall(digest_obj, id_hexdigest, 0);
}

static VALUE compute_file_digest(VALUE filename) {
  int exception_state;
  VALUE result =
      rb_protect(compute_file_digest_body, filename, &exception_state);
  if (exception_state != 0) {
    rb_set_errinfo(Qnil);
    return Qnil;
  }
  return result;
}

// Parse file with Prism and extract constant names.
static VALUE extract_const_names_body(VALUE filename) {
  return rb_funcall(cConstantExtractor, id_extract, 1, filename);
}

// Returns an array of constant name strings for a file, using the cache.
static VALUE get_const_refs_for_file(VALUE filename) {
  VALUE const_refs_hash =
      rb_hash_lookup(fast_cov_cache_hash, ID2SYM(rb_intern("const_refs")));

  VALUE cached_entry = rb_hash_lookup(const_refs_hash, filename);

  VALUE current_digest = compute_file_digest(filename);
  if (NIL_P(current_digest)) {
    if (!NIL_P(cached_entry)) {
      rb_hash_delete(const_refs_hash, filename);
    }
    return Qnil;
  }

  // Cache hit: digest matches
  if (!NIL_P(cached_entry) && RB_TYPE_P(cached_entry, T_HASH)) {
    VALUE cached_digest =
        rb_hash_lookup(cached_entry, ID2SYM(rb_intern("digest")));

    if (!NIL_P(cached_digest) &&
        rb_str_equal(cached_digest, current_digest) == Qtrue) {
      return rb_hash_lookup(cached_entry, ID2SYM(rb_intern("refs")));
    }
  }

  // Cache miss: parse with Prism and extract constant names
  int exception_state;
  VALUE const_names =
      rb_protect(extract_const_names_body, filename, &exception_state);
  if (exception_state != 0) {
    rb_set_errinfo(Qnil);
    if (!NIL_P(cached_entry)) {
      rb_hash_delete(const_refs_hash, filename);
    }
    return Qnil;
  }

  // Store in cache
  VALUE new_entry = rb_hash_new();
  rb_hash_aset(new_entry, ID2SYM(rb_intern("digest")), current_digest);
  rb_hash_aset(new_entry, ID2SYM(rb_intern("refs")), const_names);
  rb_hash_aset(const_refs_hash, filename, new_entry);

  return const_names;
}

static void resolve_constant_references(struct fast_cov_data *data) {
  VALUE seen_consts = rb_hash_new();
  VALUE processed_files = rb_hash_new();

  for (int round = 0; round < MAX_CONST_RESOLUTION_ROUNDS; round++) {
    VALUE keys = rb_funcall(data->impacted_files, id_keys, 0);
    long num_keys = RARRAY_LEN(keys);
    int found_new_file = 0;

    for (long i = 0; i < num_keys; i++) {
      VALUE filename = rb_ary_entry(keys, i);

      if (rb_hash_lookup(processed_files, filename) != Qnil) {
        continue;
      }
      rb_hash_aset(processed_files, filename, Qtrue);

      VALUE const_names = get_const_refs_for_file(filename);
      if (NIL_P(const_names) || !RB_TYPE_P(const_names, T_ARRAY)) {
        continue;
      }

      long num_refs = RARRAY_LEN(const_names);
      for (long j = 0; j < num_refs; j++) {
        VALUE const_name = rb_ary_entry(const_names, j);

        if (rb_hash_lookup(seen_consts, const_name) != Qnil) {
          continue;
        }
        rb_hash_aset(seen_consts, const_name, Qtrue);

        VALUE resolved_file = fast_cov_resolve_const_to_file(const_name);
        if (NIL_P(resolved_file)) {
          continue;
        }

        if (record_impacted_file(data, resolved_file)) {
          found_new_file = 1;
        }
      }
    }

    if (!found_new_file) {
      break;
    }
  }
}

// ---- Cache module methods (FastCov::Cache) ------------------------------

static VALUE cache_get_data(VALUE self) { return fast_cov_cache_hash; }

static VALUE cache_set_data(VALUE self, VALUE new_cache) {
  if (!RB_TYPE_P(new_cache, T_HASH)) {
    rb_raise(rb_eTypeError, "cache data must be a Hash");
  }
  rb_funcall(fast_cov_cache_hash, id_clear, 0);
  rb_funcall(fast_cov_cache_hash, id_merge_bang, 1, new_cache);
  return fast_cov_cache_hash;
}

static VALUE cache_clear(VALUE self) {
  rb_funcall(fast_cov_cache_hash, id_clear, 0);
  rb_hash_aset(fast_cov_cache_hash, ID2SYM(rb_intern("const_refs")),
               rb_hash_new());
  rb_hash_aset(fast_cov_cache_hash, ID2SYM(rb_intern("const_locations")),
               rb_hash_new());
  return Qnil;
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

  // ignored_path: optional, nil if not provided
  VALUE rb_ignored_path =
      rb_hash_lookup(opt, ID2SYM(rb_intern("ignored_path")));

  // threads: true (multi) or false (single), defaults to true
  VALUE rb_threads = rb_hash_lookup(opt, ID2SYM(rb_intern("threads")));
  bool threads = (rb_threads != Qfalse);

  // constant_references: defaults to true
  VALUE rb_const_refs =
      rb_hash_lookup(opt, ID2SYM(rb_intern("constant_references")));
  bool constant_references = (rb_const_refs != Qfalse);

  // allocations: defaults to true
  VALUE rb_allocations =
      rb_hash_lookup(opt, ID2SYM(rb_intern("allocations")));
  bool allocations = (rb_allocations != Qfalse);

  struct fast_cov_data *data;
  TypedData_Get_Struct(self, struct fast_cov_data, &fast_cov_data_type, data);

  data->threads = threads;
  data->constant_references = constant_references;
  data->allocations = allocations;
  data->root_len = RSTRING_LEN(rb_root);
  data->root =
      fast_cov_ruby_strndup(RSTRING_PTR(rb_root), data->root_len);

  if (RTEST(rb_ignored_path)) {
    data->ignored_path_len = RSTRING_LEN(rb_ignored_path);
    data->ignored_path = fast_cov_ruby_strndup(RSTRING_PTR(rb_ignored_path),
                                               data->ignored_path_len);
  }

  if (allocations) {
    data->object_allocation_tracepoint = rb_tracepoint_new(
        Qnil, RUBY_INTERNAL_EVENT_NEWOBJ, on_newobj_event, (void *)data);
  }

  return Qnil;
}

static VALUE fast_cov_start(VALUE self) {
  struct fast_cov_data *data;
  TypedData_Get_Struct(self, struct fast_cov_data, &fast_cov_data_type, data);

  if (data->root_len == 0) {
    rb_raise(rb_eRuntimeError, "root is required");
  }

  if (!data->threads) {
    VALUE thval = rb_thread_current();
    rb_thread_add_event_hook(thval, on_line_event, RUBY_EVENT_LINE, self);
    data->th_covered = thval;
  } else {
    rb_add_event_hook(on_line_event, RUBY_EVENT_LINE, self);
  }

  if (data->object_allocation_tracepoint != Qnil) {
    rb_tracepoint_enable(data->object_allocation_tracepoint);
  }

  // Block form: start { ... } runs the block then returns stop result
  if (rb_block_given_p()) {
    rb_yield(Qnil);
    return fast_cov_stop(self);
  }

  return self;
}

static VALUE fast_cov_stop(VALUE self) {
  struct fast_cov_data *data;
  TypedData_Get_Struct(self, struct fast_cov_data, &fast_cov_data_type, data);

  if (!data->threads) {
    VALUE thval = rb_thread_current();
    if (!rb_equal(thval, data->th_covered)) {
      rb_raise(rb_eRuntimeError, "Coverage was not started by this thread");
    }
    rb_thread_remove_event_hook(data->th_covered, on_line_event);
    data->th_covered = Qnil;
  } else {
    rb_remove_event_hook(on_line_event);
  }

  if (data->object_allocation_tracepoint != Qnil) {
    rb_tracepoint_disable(data->object_allocation_tracepoint);
  }

  if (data->allocations) {
    st_foreach(data->klasses_table, each_instantiated_klass, (st_data_t)data);
    st_clear(data->klasses_table);
  }

  if (data->constant_references) {
    resolve_constant_references(data);
  }

  VALUE res = data->impacted_files;

  data->impacted_files = rb_hash_new();
  data->last_filename_ptr = 0;

  return res;
}

// ---- Init ---------------------------------------------------------------

void Init_fast_cov(void) {
  id_extract = rb_intern("extract");
  id_keys = rb_intern("keys");
  id_file = rb_intern("file");
  id_hexdigest = rb_intern("hexdigest");
  id_clear = rb_intern("clear");
  id_merge_bang = rb_intern("merge!");

  rb_require("digest/md5");
  rb_require("fast_cov/constant_extractor");
  VALUE mDigest = rb_const_get(rb_cObject, rb_intern("Digest"));
  cDigest = rb_const_get(mDigest, rb_intern("MD5"));
  rb_gc_register_address(&cDigest);

  // Initialize process-level cache
  fast_cov_cache_hash = rb_hash_new();
  rb_gc_register_address(&fast_cov_cache_hash);
  rb_hash_aset(fast_cov_cache_hash, ID2SYM(rb_intern("const_refs")),
               rb_hash_new());
  rb_hash_aset(fast_cov_cache_hash, ID2SYM(rb_intern("const_locations")),
               rb_hash_new());

  VALUE mFastCov = rb_define_module("FastCov");

  // FastCov::ConstantExtractor must be loaded before the C extension
  cConstantExtractor =
      rb_const_get(mFastCov, rb_intern("ConstantExtractor"));
  rb_gc_register_address(&cConstantExtractor);

  VALUE cCoverage = rb_define_class_under(mFastCov, "Coverage", rb_cObject);

  rb_define_alloc_func(cCoverage, fast_cov_allocate);
  rb_define_method(cCoverage, "initialize", fast_cov_initialize, -1);
  rb_define_method(cCoverage, "start", fast_cov_start, 0);
  rb_define_method(cCoverage, "stop", fast_cov_stop, 0);

  // FastCov::Cache module (C-defined methods)
  VALUE mCache = rb_define_module_under(mFastCov, "Cache");
  rb_define_module_function(mCache, "data", cache_get_data, 0);
  rb_define_module_function(mCache, "data=", cache_set_data, 1);
  rb_define_module_function(mCache, "clear", cache_clear, 0);
}
