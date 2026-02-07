# frozen_string_literal: true

require "rake/extensiontask"
require "rspec/core/rake_task"

Rake::ExtensionTask.new("fast_cov") do |ext|
  ext.lib_dir = "lib/fast_cov"
end

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--fail-fast"
end

task spec: :compile
task default: :spec
