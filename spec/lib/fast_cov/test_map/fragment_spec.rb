# frozen_string_literal: true

require "zlib"
require "fileutils"
require "tmpdir"

RSpec.describe FastCov::TestMap::Fragment do
  let(:tmpdir) { Dir.mktmpdir("fast_cov_fragment") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#add and #write" do
    it "transposes spec -> dependencies to dependency -> spec_dirs" do
      fragment = described_class.new
      fragment.add("spec/models/user_spec.rb", ["app/models/user.rb", "app/helpers/user_helper.rb"])

      path = File.join(tmpdir, "output.gz")
      fragment.write(path)
      result = read_gzip(path)

      expect(result["app/models/user.rb"]).to eq(["spec/models/"])
      expect(result["app/helpers/user_helper.rb"]).to eq(["spec/models/"])
    end

    it "merges spec dirs when multiple specs depend on the same file" do
      fragment = described_class.new
      fragment.add("spec/models/user_spec.rb", ["shared.rb"])
      fragment.add("spec/controllers/users_controller_spec.rb", ["shared.rb"])

      path = File.join(tmpdir, "output.gz")
      fragment.write(path)
      result = read_gzip(path)

      expect(result["shared.rb"]).to contain_exactly("spec/controllers/", "spec/models/")
    end

    it "skips self-references" do
      fragment = described_class.new
      fragment.add("spec/models/user_spec.rb", ["spec/models/user_spec.rb", "app/models/user.rb"])

      path = File.join(tmpdir, "output.gz")
      fragment.write(path)
      result = read_gzip(path)

      expect(result).not_to have_key("spec/models/user_spec.rb")
      expect(result).to have_key("app/models/user.rb")
    end

    it "outputs sorted by file path" do
      fragment = described_class.new
      fragment.add("spec/z_spec.rb", ["z_file.rb"])
      fragment.add("spec/a_spec.rb", ["a_file.rb"])
      fragment.add("spec/m_spec.rb", ["m_file.rb"])

      path = File.join(tmpdir, "output.gz")
      fragment.write(path)
      result = read_gzip(path)

      expect(result.keys).to eq(result.keys.sort)
    end

    it "sorts spec paths within each entry" do
      fragment = described_class.new
      fragment.add("spec/z_spec.rb", ["shared.rb"])
      fragment.add("spec/a_spec.rb", ["shared.rb"])

      path = File.join(tmpdir, "output.gz")
      fragment.write(path)
      result = read_gzip(path)

      expect(result["shared.rb"]).to eq(result["shared.rb"].sort)
    end

    it "creates parent directories if needed" do
      path = File.join(tmpdir, "nested", "deep", "output.gz")
      fragment = described_class.new
      fragment.add("spec/test_spec.rb", ["file.rb"])
      fragment.write(path)

      expect(File.exist?(path)).to be true
    end
  end

  describe "#size" do
    it "returns the number of unique source files" do
      fragment = described_class.new
      fragment.add("spec/a_spec.rb", ["file1.rb", "file2.rb"])
      fragment.add("spec/b_spec.rb", ["file2.rb", "file3.rb"])

      expect(fragment.size).to eq(3)
    end
  end

  private

  def read_gzip(path)
    result = {}
    Zlib::GzipReader.open(path) do |gzip|
      gzip.each_line do |line|
        file, spec_paths_str = line.chomp.split("\t", 2)
        result[file] = spec_paths_str&.split(",") || []
      end
    end
    result
  end
end
