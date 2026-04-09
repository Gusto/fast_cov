# frozen_string_literal: true

require "zlib"
require "fileutils"
require "tmpdir"

RSpec.describe FastCov::TestMap::Reader do
  let(:tmpdir) { Dir.mktmpdir("fast_cov_reader") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "reading plain text files" do
    it "parses lines and advances through the file" do
      path = write_plain(tmpdir, "mapping.txt",
        "app/models/company.rb\ttest/models/,test/requests/",
        "app/models/user.rb\ttest/models/",
        "lib/util.rb\ttest/lib/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/company.rb")
      expect(reader.dependencies).to eq(["test/models/", "test/requests/"])
      expect(reader).not_to be_exhausted

      reader.advance
      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.dependencies).to eq(["test/models/"])

      reader.advance
      expect(reader.file_path).to eq("lib/util.rb")
      expect(reader.dependencies).to eq(["test/lib/"])

      reader.advance
      expect(reader).to be_exhausted
      expect(reader.file_path).to be_nil
      expect(reader.dependencies).to eq([])

      reader.close
    end
  end

  describe "reading gzipped files" do
    it "reads gzipped content" do
      path = write_gzip(tmpdir, "mapping.gz",
        "app/models/user.rb\ttest/models/",
        "lib/util.rb\ttest/lib/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.dependencies).to eq(["test/models/"])

      reader.advance
      expect(reader.file_path).to eq("lib/util.rb")

      reader.close
    end
  end

  describe "merging consecutive duplicate entries" do
    it "merges dependencies when the same file appears on consecutive lines" do
      path = write_plain(tmpdir, "dupes.txt",
        "app/models/user.rb\ttest/a/,test/b/",
        "app/models/user.rb\ttest/c/,test/d/",
        "app/models/widget.rb\ttest/e/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.dependencies).to contain_exactly("test/a/", "test/b/", "test/c/", "test/d/")

      reader.advance
      expect(reader.file_path).to eq("app/models/widget.rb")
      expect(reader.dependencies).to eq(["test/e/"])

      reader.advance
      expect(reader).to be_exhausted

      reader.close
    end

    it "merges more than two consecutive duplicates" do
      path = write_plain(tmpdir, "triple.txt",
        "app/models/user.rb\ttest/a/",
        "app/models/user.rb\ttest/b/",
        "app/models/user.rb\ttest/c/",
        "app/models/widget.rb\ttest/d/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.dependencies).to contain_exactly("test/a/", "test/b/", "test/c/")

      reader.close
    end

    it "merges duplicates at the end of the file" do
      path = write_plain(tmpdir, "end_dupes.txt",
        "app/models/user.rb\ttest/a/",
        "app/models/widget.rb\ttest/b/",
        "app/models/widget.rb\ttest/c/"
      )

      reader = described_class.new(path)
      reader.advance

      expect(reader.file_path).to eq("app/models/widget.rb")
      expect(reader.dependencies).to contain_exactly("test/b/", "test/c/")

      reader.close
    end

    it "does not merge non-consecutive entries" do
      path = write_plain(tmpdir, "non_consecutive.txt",
        "app/models/user.rb\ttest/a/",
        "app/models/widget.rb\ttest/b/",
        "app/models/user.rb\ttest/c/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.dependencies).to eq(["test/a/"])

      reader.advance
      expect(reader.file_path).to eq("app/models/widget.rb")

      reader.advance
      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.dependencies).to eq(["test/c/"])

      reader.close
    end
  end

  describe "edge cases" do
    it "handles empty files" do
      path = write_plain(tmpdir, "empty.txt")

      reader = described_class.new(path)

      expect(reader).to be_exhausted
      expect(reader.file_path).to be_nil

      reader.close
    end

    it "handles lines without dependencies" do
      path = write_plain(tmpdir, "no_deps.txt", "file.rb")

      reader = described_class.new(path)

      expect(reader.file_path).to eq("file.rb")
      expect(reader.dependencies).to eq([])

      reader.close
    end
  end

  private

  def write_plain(dir, name, *lines)
    path = File.join(dir, name)
    File.write(path, lines.map { |l| "#{l}\n" }.join)
    path
  end

  def write_gzip(dir, name, *lines)
    path = File.join(dir, name)
    Zlib::GzipWriter.open(path) do |gzip|
      lines.each { |l| gzip.puts(l) }
    end
    path
  end
end
