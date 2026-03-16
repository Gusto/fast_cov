#ifndef FAST_COV_H
#define FAST_COV_H

#include <ruby.h>
#include <stdbool.h>

/* ---- Path filtering ----------------------------------------------------- */

bool fast_cov_is_within_root(const char *path, long path_len,
                             const char *root, long root_len);

bool fast_cov_is_path_included(const char *path, const char *root_path,
                               long root_path_len, char **ignored_paths,
                               long *ignored_path_lens,
                               long ignored_paths_count);

/* ---- Utility functions -------------------------------------------------- */

char *fast_cov_ruby_strndup(const char *str, size_t size);

#endif /* FAST_COV_H */
