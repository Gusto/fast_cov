# frozen_string_literal: true

require "open3"
require "fileutils"

RSpec.describe "fast_cov/dev entrypoint" do
  let(:project_root) { File.expand_path("../../..", __dir__) }
  let(:lib_dir) { File.join(project_root, "lib", "fast_cov") }
  let(:bundle_glob) { File.join(lib_dir, "fast_cov.{bundle,so}") }
  let(:digest_file) { File.join(lib_dir, ".source_digest.#{RUBY_VERSION}") }

  def run_ruby(code)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, "-I", File.join(project_root, "lib"),
      "-e", code,
      chdir: project_root
    )
    [stdout + stderr, status]
  end

  def remove_compiled_extension
    Dir.glob(bundle_glob).each { |f| FileUtils.rm_f(f) }
    FileUtils.rm_f(digest_file)
  end

  after do
    # Ensure we leave a compiled extension for other tests
    system("bundle exec rake compile --silent 2>/dev/null", chdir: project_root)
  end

  it "compiles from scratch when no extension exists" do
    remove_compiled_extension

    output, status = run_ruby('require "fast_cov/dev"; puts FastCov::Coverage.new.class')

    expect(status).to be_success, "Process failed:\n#{output}"
    expect(output).to include("[FastCov] Compiling extension")
    expect(output).to include("[FastCov] Compilation complete.")
    expect(output).to include("FastCov::Coverage")
  end

  it "loads without recompiling when extension is up to date" do
    # Ensure compiled and digest exists
    remove_compiled_extension
    run_ruby('require "fast_cov/dev"')

    output, status = run_ruby('require "fast_cov/dev"; puts FastCov::Coverage.new.class')

    expect(status).to be_success, "Process failed:\n#{output}"
    expect(output).to include("[FastCov] Extension up to date")
    expect(output).to include("FastCov::Coverage")
  end

  it "recompiles when extension is missing but digest exists" do
    # Simulate: digest left behind after bundle was cleaned (e.g., different Ruby version)
    remove_compiled_extension
    run_ruby('require "fast_cov/dev"')

    # Remove only the bundle, leave the digest
    Dir.glob(bundle_glob).each { |f| FileUtils.rm_f(f) }

    output, status = run_ruby('require "fast_cov/dev"; puts FastCov::Coverage.new.class')

    expect(status).to be_success, "Process failed:\n#{output}"
    expect(output).to include("[FastCov] Compiling extension")
    expect(output).to include("[FastCov] Compilation complete.")
    expect(output).to include("FastCov::Coverage")
  end

  it "can start and stop coverage after loading via dev entrypoint" do
    output, status = run_ruby(<<~RUBY)
      require "fast_cov/dev"
      cov = FastCov::Coverage.new(root: "#{project_root}/spec/fixtures/calculator")
      cov.start
      result = cov.stop
      puts result.class
    RUBY

    expect(status).to be_success, "Process failed:\n#{output}"
    expect(output).to include("Hash")
  end
end
