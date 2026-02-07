#include "fast_cov.h"
#include <ruby.h>
#include <string.h>

bool fast_cov_is_path_included(const char *path, const char *root_path,
                               long root_path_len, const char *ignored_path,
                               long ignored_path_len) {
  if (strncmp(root_path, path, root_path_len) != 0) {
    return false;
  }
  if (ignored_path_len > 0 &&
      strncmp(ignored_path, path, ignored_path_len) == 0) {
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

  return filename;
}
