# frozen_string_literal: true

require "rspec/core/rake_task"
require "fileutils"

desc "Compile the C extension for the current Ruby version"
task compile: :clean do
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

  FileUtils.rm_f(Dir.glob(File.join(lib_dir, "fast_cov.{bundle,so}")))
  FileUtils.rm_f(Dir.glob(File.join(lib_dir, ".source_digest.*")))
  FileUtils.rm_f(Dir.glob(File.join(ext_dir, "*.{o,bundle,so}")))
  FileUtils.rm_f(File.join(ext_dir, "Makefile"))
  FileUtils.rm_f(File.join(ext_dir, "mkmf.log"))
end

desc "Run specs (in subprocess to avoid Ruby 3.4 extension loading issues)"
task spec: :compile do
  sh "bundle", "exec", "rspec", "--fail-fast"
end
task default: :spec
