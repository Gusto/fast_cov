# frozen_string_literal: true

# Auto-compile entrypoint for local development with path: Gemfile references.
#
# Usage in a consuming project's Gemfile:
#   gem "fast_cov", path: "../fast_cov", require: "fast_cov/dev"
#
# Compiles the C extension if:
#   - It hasn't been compiled for this Ruby version yet
#   - The C source files have changed since the last compilation

require_relative "compiler"

if FastCov::Compiler.stale?
  $stdout.puts "[FastCov] Compiling extension for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})..."
  FastCov::Compiler.compile!
  $stdout.puts "[FastCov] Compilation complete."
else
  $stdout.puts "[FastCov] Extension up to date for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
end

require_relative "../fast_cov"
