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
        "app/models/company.rb\tspec/models/,spec/requests/",
        "app/models/user.rb\tspec/models/",
        "lib/util.rb\tspec/lib/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/company.rb")
      expect(reader.spec_paths).to eq(["spec/models/", "spec/requests/"])
      expect(reader).not_to be_exhausted

      reader.advance
      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.spec_paths).to eq(["spec/models/"])

      reader.advance
      expect(reader.file_path).to eq("lib/util.rb")
      expect(reader.spec_paths).to eq(["spec/lib/"])

      reader.advance
      expect(reader).to be_exhausted
      expect(reader.file_path).to be_nil
      expect(reader.spec_paths).to eq([])

      reader.close
    end
  end

  describe "reading gzipped files" do
    it "reads gzipped content" do
      path = write_gzip(tmpdir, "mapping.gz",
        "app/models/user.rb\tspec/models/",
        "lib/util.rb\tspec/lib/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.spec_paths).to eq(["spec/models/"])

      reader.advance
      expect(reader.file_path).to eq("lib/util.rb")

      reader.close
    end
  end

  describe "merging consecutive duplicate entries" do
    it "merges spec paths when the same file appears on consecutive lines" do
      path = write_plain(tmpdir, "dupes.txt",
        "app/models/user.rb\tspec/a/,spec/b/",
        "app/models/user.rb\tspec/c/,spec/d/",
        "app/models/widget.rb\tspec/e/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.spec_paths).to contain_exactly("spec/a/", "spec/b/", "spec/c/", "spec/d/")

      reader.advance
      expect(reader.file_path).to eq("app/models/widget.rb")
      expect(reader.spec_paths).to eq(["spec/e/"])

      reader.advance
      expect(reader).to be_exhausted

      reader.close
    end

    it "merges more than two consecutive duplicates" do
      path = write_plain(tmpdir, "triple.txt",
        "app/models/user.rb\tspec/a/",
        "app/models/user.rb\tspec/b/",
        "app/models/user.rb\tspec/c/",
        "app/models/widget.rb\tspec/d/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.spec_paths).to contain_exactly("spec/a/", "spec/b/", "spec/c/")

      reader.close
    end

    it "merges duplicates at the end of the file" do
      path = write_plain(tmpdir, "end_dupes.txt",
        "app/models/user.rb\tspec/a/",
        "app/models/widget.rb\tspec/b/",
        "app/models/widget.rb\tspec/c/"
      )

      reader = described_class.new(path)
      reader.advance

      expect(reader.file_path).to eq("app/models/widget.rb")
      expect(reader.spec_paths).to contain_exactly("spec/b/", "spec/c/")

      reader.close
    end

    it "does not merge non-consecutive entries" do
      path = write_plain(tmpdir, "non_consecutive.txt",
        "app/models/user.rb\tspec/a/",
        "app/models/widget.rb\tspec/b/",
        "app/models/user.rb\tspec/c/"
      )

      reader = described_class.new(path)

      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.spec_paths).to eq(["spec/a/"])

      reader.advance
      expect(reader.file_path).to eq("app/models/widget.rb")

      reader.advance
      expect(reader.file_path).to eq("app/models/user.rb")
      expect(reader.spec_paths).to eq(["spec/c/"])

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

    it "handles lines without spec_paths" do
      path = write_plain(tmpdir, "no_specs.txt", "file.rb")

      reader = described_class.new(path)

      expect(reader.file_path).to eq("file.rb")
      expect(reader.spec_paths).to eq([])

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
