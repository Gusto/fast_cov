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
                               long root_path_len, char **ignored_paths,
                               long *ignored_path_lens,
                               long ignored_paths_count) {
  long path_len = (long)strlen(path);
  long i;

  if (!fast_cov_is_within_root(path, path_len, root_path, root_path_len)) {
    return false;
  }

  for (i = 0; i < ignored_paths_count; i++) {
    if (fast_cov_is_within_root(path, path_len, ignored_paths[i],
                                ignored_path_lens[i])) {
      return false;
    }
  }

  return true;
}

char *fast_cov_ruby_strndup(const char *str, size_t size) {
  char *dup = xmalloc(size + 1);
  memcpy(dup, str, size);
  dup[size] = '\0';
  return dup;
}
