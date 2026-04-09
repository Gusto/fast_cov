# frozen_string_literal: true

require "zlib"
require "fileutils"
require "tmpdir"

RSpec.describe FastCov::TestMap do
  let(:tmpdir) { Dir.mktmpdir("fast_cov_test_map") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#add" do
    it "records spec -> dependency mappings" do
      test_map = described_class.new
      test_map.add("spec/models/user_spec.rb" => ["app/models/user.rb", "app/helpers/user_helper.rb"])

      expect(test_map.dependencies("app/models/user.rb")).to eq(["spec/models/user_spec.rb"])
      expect(test_map.dependencies("app/helpers/user_helper.rb")).to eq(["spec/models/user_spec.rb"])
    end

    it "merges spec paths when multiple specs depend on the same file" do
      test_map = described_class.new
      test_map.add("spec/models/user_spec.rb" => ["shared.rb"])
      test_map.add("spec/controllers/users_controller_spec.rb" => ["shared.rb"])

      expect(test_map.dependencies("shared.rb")).to contain_exactly(
        "spec/models/user_spec.rb",
        "spec/controllers/users_controller_spec.rb"
      )
    end

    it "skips self-references" do
      test_map = described_class.new
      test_map.add("spec/models/user_spec.rb" => ["spec/models/user_spec.rb", "app/models/user.rb"])

      expect(test_map.dependencies("spec/models/user_spec.rb")).to be_empty
      expect(test_map.dependencies("app/models/user.rb")).to eq(["spec/models/user_spec.rb"])
    end

    it "accepts multiple mappings in one call" do
      test_map = described_class.new
      test_map.add(
        "spec/models/user_spec.rb" => ["app/models/user.rb"],
        "spec/models/company_spec.rb" => ["app/models/company.rb"]
      )

      expect(test_map.dependencies("app/models/user.rb")).to eq(["spec/models/user_spec.rb"])
      expect(test_map.dependencies("app/models/company.rb")).to eq(["spec/models/company_spec.rb"])
    end
  end

  describe "#dependencies" do
    it "returns an empty array for unknown files" do
      test_map = described_class.new

      expect(test_map.dependencies("unknown.rb")).to eq([])
    end
  end

  describe "#dump" do
    it "writes gzipped TSV sorted by file path" do
      test_map = described_class.new
      test_map.add("spec/models/user_spec.rb" => ["z_file.rb", "a_file.rb"])

      path = File.join(tmpdir, "output.gz")
      test_map.dump(path)
      result = read_gzip(path)

      expect(result.keys).to eq(["a_file.rb", "z_file.rb"])
    end

    it "sorts spec paths within each entry" do
      test_map = described_class.new
      test_map.add("spec/z_spec.rb" => ["shared.rb"])
      test_map.add("spec/a_spec.rb" => ["shared.rb"])

      path = File.join(tmpdir, "output.gz")
      test_map.dump(path)
      result = read_gzip(path)

      expect(result["shared.rb"]).to eq(result["shared.rb"].sort)
    end

    it "creates parent directories if needed" do
      test_map = described_class.new
      test_map.add("spec/test_spec.rb" => ["file.rb"])

      path = File.join(tmpdir, "nested", "deep", "output.gz")
      test_map.dump(path)

      expect(File.exist?(path)).to be true
    end
  end

  describe "#size" do
    it "returns the number of unique source files" do
      test_map = described_class.new
      test_map.add("spec/a_spec.rb" => ["file1.rb", "file2.rb"])
      test_map.add("spec/b_spec.rb" => ["file2.rb", "file3.rb"])

      expect(test_map.size).to eq(3)
    end
  end

  describe ".aggregate" do
    it "merges multiple fragments and yields unique files with merged spec paths" do
      f1 = write_fragment(tmpdir, "f1.gz", {
        "app/models/user.rb" => "spec/models/user_spec.rb",
        "app/models/company.rb" => "spec/models/company_spec.rb"
      })
      f2 = write_fragment(tmpdir, "f2.gz", {
        "app/models/user.rb" => "spec/controllers/users_controller_spec.rb",
        "lib/util.rb" => "spec/lib/util_spec.rb"
      })

      results = {}
      described_class.aggregate(f1, f2) { |file, sp| results[file] = sp }

      expect(results["app/models/user.rb"]).to contain_exactly(
        "spec/controllers/users_controller_spec.rb",
        "spec/models/user_spec.rb"
      )
      expect(results["app/models/company.rb"]).to eq(["spec/models/company_spec.rb"])
      expect(results["lib/util.rb"]).to eq(["spec/lib/util_spec.rb"])
    end

    it "returns the number of unique files" do
      f1 = write_fragment(tmpdir, "f1.gz", { "a.rb" => "spec/a.rb", "b.rb" => "spec/b.rb" })
      f2 = write_fragment(tmpdir, "f2.gz", { "a.rb" => "spec/c.rb", "c.rb" => "spec/c.rb" })

      count = described_class.aggregate(f1, f2) { |_f, _sp| }

      expect(count).to eq(3)
    end

    it "accepts glob patterns" do
      write_fragment(tmpdir, "node_0.gz", { "a.rb" => "spec/a.rb" })
      write_fragment(tmpdir, "node_1.gz", { "b.rb" => "spec/b.rb" })

      results = {}
      described_class.aggregate(File.join(tmpdir, "node_*.gz")) { |file, sp| results[file] = sp }

      expect(results).to have_key("a.rb")
      expect(results).to have_key("b.rb")
    end

    it "raises without a block" do
      expect { described_class.aggregate("anything") }.to raise_error(ArgumentError, /block/)
    end

    it "returns 0 for empty fragment list" do
      count = described_class.aggregate { |_f, _sp| }

      expect(count).to eq(0)
    end

    it "deduplicates spec paths across fragments" do
      f1 = write_fragment(tmpdir, "f1.gz", { "shared.rb" => "spec/a.rb" })
      f2 = write_fragment(tmpdir, "f2.gz", { "shared.rb" => "spec/a.rb" })

      results = {}
      described_class.aggregate(f1, f2) { |file, sp| results[file] = sp }

      expect(results["shared.rb"]).to eq(["spec/a.rb"])
    end

    it "yields files in sorted order" do
      f1 = write_fragment(tmpdir, "f1.gz", { "z.rb" => "spec/z.rb", "a.rb" => "spec/a.rb" })
      f2 = write_fragment(tmpdir, "f2.gz", { "m.rb" => "spec/m.rb" })

      order = []
      described_class.aggregate(f1, f2) { |file, _sp| order << file }

      expect(order).to eq(order.sort)
    end

    it "round-trips through dump and aggregate" do
      map1 = described_class.new
      map1.add("spec/models/user_spec.rb" => ["app/models/user.rb", "shared.rb"])
      map1.add("spec/models/company_spec.rb" => ["app/models/company.rb"])
      f1 = File.join(tmpdir, "map1.gz")
      map1.dump(f1)

      map2 = described_class.new
      map2.add("spec/controllers/users_controller_spec.rb" => ["app/models/user.rb", "shared.rb"])
      f2 = File.join(tmpdir, "map2.gz")
      map2.dump(f2)

      results = {}
      described_class.aggregate(f1, f2) { |file, sp| results[file] = sp }

      expect(results["app/models/user.rb"]).to contain_exactly(
        "spec/controllers/users_controller_spec.rb",
        "spec/models/user_spec.rb"
      )
      expect(results["shared.rb"]).to contain_exactly(
        "spec/controllers/users_controller_spec.rb",
        "spec/models/user_spec.rb"
      )
      expect(results["app/models/company.rb"]).to eq(["spec/models/company_spec.rb"])
    end
  end

  describe "intermediate batching" do
    it "creates intermediates when fragment count exceeds max_readers" do
      fragments = 5.times.map do |i|
        write_fragment(tmpdir, "f#{i}.gz", { "file_#{i}.rb" => "spec/#{i}.rb" })
      end

      intermediates_dir = File.join(tmpdir, "intermediates")
      results = {}
      described_class.aggregate(*fragments, max_readers: 2, intermediates_dir: intermediates_dir) do |file, sp|
        results[file] = sp
      end

      expect(results.size).to eq(5)
      expect(Dir.exist?(intermediates_dir)).to be false
    end

    it "merges overlapping entries across intermediates" do
      fragments = 10.times.map do |i|
        write_fragment(tmpdir, "f#{i}.gz", { "shared.rb" => "spec/#{i}.rb" })
      end

      results = {}
      described_class.aggregate(*fragments, max_readers: 3, intermediates_dir: File.join(tmpdir, "intermediates")) do |file, sp|
        results[file] = sp
      end

      expect(results["shared.rb"].size).to eq(10)
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

  def write_fragment(dir, name, mapping)
    path = File.join(dir, name)
    Zlib::GzipWriter.open(path) do |gzip|
      mapping.keys.sort.each do |file|
        gzip.puts("#{file}\t#{mapping[file]}")
      end
    end
    path
  end
end
