# frozen_string_literal: true

require "zlib"
require "fileutils"
require "tmpdir"

RSpec.describe FastCov::TestMap do
  let(:tmpdir) { Dir.mktmpdir("fast_cov_test_map") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#add" do
    it "records test -> dependency mappings" do
      test_map = described_class.new
      test_map.add("spec/models/user_spec.rb" => ["app/models/user.rb", "app/helpers/user_helper.rb"])

      expect(test_map.dependencies("app/models/user.rb")).to eq(["spec/models/user_spec.rb"])
      expect(test_map.dependencies("app/helpers/user_helper.rb")).to eq(["spec/models/user_spec.rb"])
    end

    it "merges dependencies when multiple tests depend on the same file" do
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

      expect(test_map.dependencies("spec/models/user_spec.rb")).to be_nil
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
    it "returns nil for unknown files" do
      test_map = described_class.new

      expect(test_map.dependencies("unknown.rb")).to be_nil
    end
  end

  describe "#dump" do
    it "writes gzipped TSV" do
      test_map = described_class.new
      test_map.add("spec/models/user_spec.rb" => ["z_file.rb", "a_file.rb"])

      path = File.join(tmpdir, "output.gz")
      test_map.dump(path)
      result = read_gzip(path)

      expect(result).to have_key("a_file.rb")
      expect(result).to have_key("z_file.rb")
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
    describe "#each" do
      it "yields hashes with merged dependencies" do
        f1 = write_fragment(tmpdir, "f1.gz", {
          "app/models/user.rb" => "spec/models/user_spec.rb",
          "app/models/company.rb" => "spec/models/company_spec.rb"
        })
        f2 = write_fragment(tmpdir, "f2.gz", {
          "app/models/user.rb" => "spec/controllers/users_controller_spec.rb",
          "lib/util.rb" => "spec/lib/util_spec.rb"
        })

        results = {}
        described_class.aggregate(f1, f2).each { |batch| results.merge!(batch) }

        expect(results["app/models/user.rb"]).to contain_exactly(
          "spec/controllers/users_controller_spec.rb",
          "spec/models/user_spec.rb"
        )
        expect(results["app/models/company.rb"]).to eq(["spec/models/company_spec.rb"])
        expect(results["lib/util.rb"]).to eq(["spec/lib/util_spec.rb"])
      end

      it "deduplicates dependencies across fragments" do
        f1 = write_fragment(tmpdir, "f1.gz", { "shared.rb" => "spec/a.rb" })
        f2 = write_fragment(tmpdir, "f2.gz", { "shared.rb" => "spec/a.rb" })

        results = {}
        described_class.aggregate(f1, f2).each { |batch| results.merge!(batch) }

        expect(results["shared.rb"]).to eq(["spec/a.rb"])
      end

      it "yields files in sorted order" do
        f1 = write_fragment(tmpdir, "f1.gz", { "z.rb" => "spec/z.rb", "a.rb" => "spec/a.rb" })
        f2 = write_fragment(tmpdir, "f2.gz", { "m.rb" => "spec/m.rb" })

        order = []
        described_class.aggregate(f1, f2).each { |batch| order.concat(batch.keys) }

        expect(order).to eq(order.sort)
      end

      it "batches entries by batch_size" do
        f1 = write_fragment(tmpdir, "f1.gz", {
          "a.rb" => "spec/a.rb",
          "b.rb" => "spec/b.rb",
          "c.rb" => "spec/c.rb"
        })

        batches = []
        described_class.aggregate(f1).each(2) { |batch| batches << batch }

        expect(batches.size).to eq(2)
        expect(batches[0].size).to eq(2)
        expect(batches[1].size).to eq(1)
        expect(batches.flat_map(&:keys)).to contain_exactly("a.rb", "b.rb", "c.rb")
      end

      it "handles exact batch_size multiples" do
        f1 = write_fragment(tmpdir, "f1.gz", {
          "a.rb" => "spec/a.rb",
          "b.rb" => "spec/b.rb"
        })

        batches = []
        described_class.aggregate(f1).each(2) { |batch| batches << batch }

        expect(batches.size).to eq(1)
        expect(batches[0].size).to eq(2)
      end

      it "raises without a block" do
        expect { described_class.aggregate.each }.to raise_error(ArgumentError, /block/)
      end

      it "does not yield for empty fragments" do
        yielded = false
        described_class.aggregate.each { |_batch| yielded = true }

        expect(yielded).to be false
      end
    end

    describe "glob patterns" do
      it "expands glob patterns" do
        write_fragment(tmpdir, "node_0.gz", { "a.rb" => "spec/a.rb" })
        write_fragment(tmpdir, "node_1.gz", { "b.rb" => "spec/b.rb" })

        results = {}
        described_class.aggregate(File.join(tmpdir, "node_*.gz")).each { |batch| results.merge!(batch) }

        expect(results).to have_key("a.rb")
        expect(results).to have_key("b.rb")
      end
    end

    describe "hooks" do
      it "emits :sort and :sorted events" do
        f1 = write_fragment(tmpdir, "f1.gz", { "a.rb" => "spec/a.rb" })
        f2 = write_fragment(tmpdir, "f2.gz", { "b.rb" => "spec/b.rb" })

        sort_args = nil
        sorted_elapsed = nil

        aggregator = described_class.aggregate(f1, f2)
        aggregator.on(:sort) { |fragments, batches| sort_args = [fragments, batches] }
        aggregator.on(:sorted) { |elapsed| sorted_elapsed = elapsed }
        aggregator.each { |_batch| }

        expect(sort_args).to eq([2, 2])
        expect(sorted_elapsed).to be_a(Float)
        expect(sorted_elapsed).to be >= 0
      end

      it "emits :merged event" do
        f1 = write_fragment(tmpdir, "f1.gz", { "a.rb" => "spec/a.rb", "b.rb" => "spec/b.rb" })

        merged_args = nil

        aggregator = described_class.aggregate(f1)
        aggregator.on(:merged) { |files, elapsed| merged_args = [files, elapsed] }
        aggregator.each { |_batch| }

        expect(merged_args[0]).to eq(2)
        expect(merged_args[1]).to be_a(Float)
      end

      it "supports chaining on calls" do
        f1 = write_fragment(tmpdir, "f1.gz", { "a.rb" => "spec/a.rb" })

        events = []
        described_class.aggregate(f1)
          .on(:sort) { |*_| events << :sort }
          .on(:sorted) { |*_| events << :sorted }
          .on(:merged) { |*_| events << :merged }
          .each { |_batch| }

        expect(events).to eq([:sort, :sorted, :merged])
      end
    end

    describe "round-trip" do
      it "dumps and aggregates correctly" do
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
        described_class.aggregate(f1, f2).each { |batch| results.merge!(batch) }

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
      it "merges overlapping entries across intermediates" do
        fragments = 10.times.map do |i|
          write_fragment(tmpdir, "f#{i}.gz", { "shared.rb" => "test/#{i}.rb" })
        end

        results = {}
        described_class.aggregate(*fragments, readers: 3).each { |batch| results.merge!(batch) }

        expect(results["shared.rb"].size).to eq(10)
      end
    end
  end

  private

  def read_gzip(path)
    result = {}
    Zlib::GzipReader.open(path) do |gzip|
      gzip.each_line do |line|
        parts = line.chomp.split("\t")
        result[parts[0]] = parts[1..] || []
      end
    end
    result
  end

  def write_fragment(dir, name, mapping)
    path = File.join(dir, name)
    Zlib::GzipWriter.open(path) do |gzip|
      mapping.each do |file, deps|
        deps = Array(deps)
        gzip.puts([file, *deps].join("\t"))
      end
    end
    path
  end
end
