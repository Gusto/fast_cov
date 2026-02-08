# frozen_string_literal: true

# Auto-compile entrypoint for local development with path: Gemfile references.
#
# Usage in a consuming project's Gemfile:
#   gem "fast_cov", path: "../fast_cov", require: "fast_cov/compile"
#
# Compiles the C extension for the current Ruby version if needed,
# then loads FastCov normally.

require_relative "compiler"

ext_name = "fast_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

begin
  require_relative ext_name
  $stdout.puts "[FastCov] Loaded pre-compiled extension for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
rescue LoadError
  $stdout.puts "[FastCov] Compiling extension for Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})..."
  FastCov::Compiler.compile!
  require_relative ext_name
  $stdout.puts "[FastCov] Compilation complete."
end

require_relative "../fast_cov"
