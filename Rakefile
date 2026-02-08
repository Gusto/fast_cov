# frozen_string_literal: true

require "rspec/core/rake_task"
require "fileutils"

desc "Compile the C extension for the current Ruby version"
task :compile do
  ext_dir = File.expand_path("ext/fast_cov", __dir__)
  lib_dir = File.expand_path("lib/fast_cov", __dir__)

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

  FileUtils.rm_f(Dir.glob(File.join(lib_dir, "*.{bundle,so}")))
  FileUtils.rm_f(Dir.glob(File.join(ext_dir, "*.{o,bundle,so}")))
  FileUtils.rm_f(File.join(ext_dir, "Makefile"))
  FileUtils.rm_f(File.join(ext_dir, "mkmf.log"))
  FileUtils.rm_rf(File.expand_path("tmp", __dir__))
end

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--fail-fast"
end

task spec: :compile
task default: :spec
