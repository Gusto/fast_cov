# frozen_string_literal: true

# Auto-compile entrypoint for local development with path: Gemfile references.
#
# Usage in a consuming project's Gemfile:
#   gem "fast_cov", path: "../fast_cov", require: "fast_cov/compile"
#
# Compiles the C extension if:
#   - It hasn't been compiled for this Ruby version yet
#   - The C source files have changed since the last compilation

require_relative "compiler"

ext_name = "fast_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

compiled = begin
  require_relative ext_name
  true
rescue LoadError
  false
end

if compiled && !FastCov::Compiler.stale?
  $stdout.puts "[FastCov] Extension up to date for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
elsif compiled
  $stdout.puts "[FastCov] Source changed, recompiling for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})..."
  FastCov::Compiler.compile!
  $stdout.puts "[FastCov] Done. Restart required for changes to take effect."
else
  $stdout.puts "[FastCov] Compiling extension for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})..."
  FastCov::Compiler.compile!
  require_relative ext_name
  $stdout.puts "[FastCov] Compilation complete."
end

require_relative "../fast_cov"
