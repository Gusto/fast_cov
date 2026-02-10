# frozen_string_literal: true

require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "gem installation", :slow do
  let(:project_root) { File.expand_path("../../..", __dir__) }

  it "loads correctly when installed as a gem" do
    Dir.mktmpdir do |tmpdir|
      gem_home = File.join(tmpdir, "gems")
      FileUtils.mkdir_p(gem_home)

      # Build the gem
      gem_file = Dir.chdir(project_root) do
        output, status = Open3.capture2e("gem build fast_cov.gemspec")
        expect(status).to be_success, "gem build failed:\n#{output}"
        Dir.glob("fast_cov-*.gem").first
      end

      # Install to temp directory
      output, status = Open3.capture2e(
        "gem install #{File.join(project_root, gem_file)} --install-dir #{gem_home} --no-document"
      )
      expect(status).to be_success, "gem install failed:\n#{output}"

      # Verify it loads and works
      test_script = <<~RUBY
        require 'fast_cov'
        cov = FastCov::Coverage.new(root: Dir.pwd)
        cov.start
        result = cov.stop
        puts result.class
      RUBY

      # Isolate from bundler - use clean env and run from temp dir
      env = {
        "GEM_HOME" => gem_home,
        "GEM_PATH" => gem_home,
        "BUNDLE_GEMFILE" => "",
        "RUBYOPT" => ""
      }
      output, status = Open3.capture2e(
        env,
        RbConfig.ruby, "--disable-gems", "-r", "rubygems", "-e", test_script,
        chdir: tmpdir
      )

      expect(status).to be_success, "Loading installed gem failed:\n#{output}"
      expect(output.strip).to eq("Hash")
    ensure
      # Clean up built gem
      FileUtils.rm_f(File.join(project_root, gem_file)) if gem_file
    end
  end
end
