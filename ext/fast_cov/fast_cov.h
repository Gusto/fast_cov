#ifndef FAST_COV_H
#define FAST_COV_H

#include <ruby.h>
#include <stdbool.h>

/* ---- Cache -------------------------------------------------------------- */

extern VALUE fast_cov_cache_hash;

/* ---- Path filtering ----------------------------------------------------- */

bool fast_cov_is_path_included(const char *path, const char *root_path,
                               long root_path_len, const char *ignored_path,
                               long ignored_path_len);

/* ---- Utility functions -------------------------------------------------- */

char *fast_cov_ruby_strndup(const char *str, size_t size);

VALUE fast_cov_rescue_nil(VALUE (*fn)(VALUE), VALUE arg);

VALUE fast_cov_get_const_source_location(VALUE const_name_str);

VALUE fast_cov_safely_get_const_source_location(VALUE const_name_str);

VALUE fast_cov_resolve_const_to_file(VALUE const_name_str);

#endif /* FAST_COV_H */
