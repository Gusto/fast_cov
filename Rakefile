# frozen_string_literal: true

require "rspec/core/rake_task"
require "fileutils"

GEMSPEC = Gem::Specification.load("fast_cov.gemspec")

desc "Compile the C extension for the current Ruby version"
task :compile do
  ext_dir = File.expand_path("ext/fast_cov", __dir__)
  lib_dir = File.expand_path("lib", __dir__)

  Dir.chdir(ext_dir) do
    sh RbConfig.ruby, "extconf.rb"
    sh "make"
    sh "make install sitearchdir=#{lib_dir} sitelibdir=#{lib_dir}"
  end
end

desc "Remove all compiled extensions and build artifacts"
task :clean do
  ext_dir = File.expand_path("ext/fast_cov", __dir__)
  lib_dir = File.expand_path("lib/fast_cov", __dir__)

  FileUtils.rm_f(Dir.glob(File.join(lib_dir, "fast_cov.*.{bundle,so}")))
  FileUtils.rm_f(Dir.glob(File.join(lib_dir, ".source_digest.*")))
  FileUtils.rm_f(Dir.glob(File.join(ext_dir, "*.{o,bundle,so}")))
  FileUtils.rm_f(File.join(ext_dir, "Makefile"))
  FileUtils.rm_f(File.join(ext_dir, "mkmf.log"))
  FileUtils.rm_rf("pkg")
  FileUtils.rm_rf("tmp")
end

desc "Run specs (compiles first)"
task spec: :compile do
  sh "bundle", "exec", "rspec", "--fail-fast"
end

desc "Build gem"
task :gem => :clean do
  sh "gem build fast_cov.gemspec"
end

task default: :spec
