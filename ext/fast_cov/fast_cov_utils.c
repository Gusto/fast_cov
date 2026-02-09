#include "fast_cov.h"
#include <ruby.h>
#include <string.h>

// Check if path is within root directory.
// Handles trailing slashes on root and ensures we don't match
// /a/b/c against /a/b/cd (sibling directory with longer name).
bool fast_cov_is_within_root(const char *path, long path_len,
                             const char *root, long root_len) {
  // Normalize: strip trailing slash from root for comparison
  long effective_root_len = root_len;
  if (effective_root_len > 0 && root[effective_root_len - 1] == '/') {
    effective_root_len--;
  }

  // Path must be at least as long as root
  if (path_len < effective_root_len) {
    return false;
  }

  // Check prefix match
  if (strncmp(path, root, effective_root_len) != 0) {
    return false;
  }

  // Path is exactly root (rare but valid)
  if (path_len == effective_root_len) {
    return true;
  }

  // Path must have '/' immediately after root prefix
  // This prevents /a/b/c from matching /a/b/cd
  return path[effective_root_len] == '/';
}

bool fast_cov_is_path_included(const char *path, const char *root_path,
                               long root_path_len, const char *ignored_path,
                               long ignored_path_len) {
  long path_len = (long)strlen(path);

  if (!fast_cov_is_within_root(path, path_len, root_path, root_path_len)) {
    return false;
  }
  if (ignored_path_len > 0 &&
      fast_cov_is_within_root(path, path_len, ignored_path, ignored_path_len)) {
    return false;
  }
  return true;
}

char *fast_cov_ruby_strndup(const char *str, size_t size) {
  char *dup = xmalloc(size + 1);
  memcpy(dup, str, size);
  dup[size] = '\0';
  return dup;
}

VALUE fast_cov_rescue_nil(VALUE (*fn)(VALUE), VALUE arg) {
  int exception_state;
  VALUE result = rb_protect(fn, arg, &exception_state);
  if (exception_state != 0) {
    rb_set_errinfo(Qnil);
    return Qnil;
  }
  return result;
}

VALUE fast_cov_get_const_source_location(VALUE const_name_str) {
  return rb_funcall(rb_cObject, rb_intern("const_source_location"), 1,
                    const_name_str);
}

VALUE fast_cov_safely_get_const_source_location(VALUE const_name_str) {
  return fast_cov_rescue_nil(fast_cov_get_const_source_location,
                             const_name_str);
}

VALUE fast_cov_resolve_const_to_file(VALUE const_name_str) {
  // Check cache first
  VALUE const_locations_hash =
      rb_hash_lookup(fast_cov_cache_hash, ID2SYM(rb_intern("const_locations")));
  VALUE cached = rb_hash_lookup(const_locations_hash, const_name_str);
  if (cached != Qnil) {
    return cached;
  }

  // Cache miss - resolve via Object.const_source_location
  VALUE source_location =
      fast_cov_safely_get_const_source_location(const_name_str);
  if (NIL_P(source_location) || !RB_TYPE_P(source_location, T_ARRAY) ||
      RARRAY_LEN(source_location) == 0) {
    return Qnil;
  }

  VALUE filename = RARRAY_AREF(source_location, 0);
  if (NIL_P(filename) || !RB_TYPE_P(filename, T_STRING)) {
    return Qnil;
  }

  // Cache the result
  rb_hash_aset(const_locations_hash, const_name_str, filename);

  return filename;
}
