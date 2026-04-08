# frozen_string_literal: true

require "zlib"
require "fileutils"
require "tmpdir"

RSpec.describe FastCov::TestMap do
  let(:tmpdir) { Dir.mktmpdir("fast_cov_test_map") }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#build" do
    it "merges multiple fragments and yields unique files with merged spec paths" do
      f1 = write_fragment(tmpdir, "f1.gz", {
        "app/models/user.rb" => "spec/models/",
        "app/models/company.rb" => "spec/models/"
      })
      f2 = write_fragment(tmpdir, "f2.gz", {
        "app/models/user.rb" => "spec/controllers/",
        "lib/util.rb" => "spec/lib/"
      })

      results = {}
      described_class.new.build([f1, f2]) do |file, spec_paths|
        results[file] = spec_paths
      end

      expect(results["app/models/user.rb"]).to contain_exactly("spec/controllers/", "spec/models/")
      expect(results["app/models/company.rb"]).to eq(["spec/models/"])
      expect(results["lib/util.rb"]).to eq(["spec/lib/"])
    end

    it "returns the number of unique files" do
      f1 = write_fragment(tmpdir, "f1.gz", { "a.rb" => "spec/a/", "b.rb" => "spec/b/" })
      f2 = write_fragment(tmpdir, "f2.gz", { "a.rb" => "spec/c/", "c.rb" => "spec/c/" })

      count = described_class.new.build([f1, f2]) { |_f, _sp| }

      expect(count).to eq(3)
    end

    it "raises without a block" do
      expect { described_class.new.build([]) }.to raise_error(ArgumentError, /block/)
    end

    it "returns 0 for empty fragment list" do
      count = described_class.new.build([]) { |_f, _sp| }

      expect(count).to eq(0)
    end

    it "handles a single fragment" do
      f1 = write_fragment(tmpdir, "f1.gz", {
        "a.rb" => "spec/a/",
        "b.rb" => "spec/b/"
      })

      results = {}
      described_class.new.build([f1]) { |file, sp| results[file] = sp }

      expect(results.size).to eq(2)
      expect(results["a.rb"]).to eq(["spec/a/"])
    end

    it "deduplicates spec paths across fragments" do
      f1 = write_fragment(tmpdir, "f1.gz", { "shared.rb" => "spec/models/" })
      f2 = write_fragment(tmpdir, "f2.gz", { "shared.rb" => "spec/models/" })

      results = {}
      described_class.new.build([f1, f2]) { |file, sp| results[file] = sp }

      expect(results["shared.rb"]).to eq(["spec/models/"])
    end

    it "yields files in sorted order" do
      f1 = write_fragment(tmpdir, "f1.gz", { "z.rb" => "spec/z/", "a.rb" => "spec/a/" })
      f2 = write_fragment(tmpdir, "f2.gz", { "m.rb" => "spec/m/" })

      order = []
      described_class.new.build([f1, f2]) { |file, _sp| order << file }

      expect(order).to eq(order.sort)
    end

    it "round-trips through Fragment and build" do
      frag1 = FastCov::TestMap::Fragment.new
      frag1.add("spec/models/user_spec.rb", ["app/models/user.rb", "shared.rb"])
      frag1.add("spec/models/company_spec.rb", ["app/models/company.rb"])
      f1_path = File.join(tmpdir, "frag1.gz")
      frag1.write(f1_path)

      frag2 = FastCov::TestMap::Fragment.new
      frag2.add("spec/controllers/users_controller_spec.rb", ["app/models/user.rb", "shared.rb"])
      f2_path = File.join(tmpdir, "frag2.gz")
      frag2.write(f2_path)

      results = {}
      described_class.new.build([f1_path, f2_path]) { |file, sp| results[file] = sp }

      expect(results["app/models/user.rb"]).to contain_exactly("spec/controllers/", "spec/models/")
      expect(results["shared.rb"]).to contain_exactly("spec/controllers/", "spec/models/")
      expect(results["app/models/company.rb"]).to eq(["spec/models/"])
    end
  end

  describe "intermediate batching" do
    it "creates intermediates when fragment count exceeds max_readers" do
      # Create 5 fragments, set max_readers to 2 to force batching
      fragments = 5.times.map do |i|
        write_fragment(tmpdir, "f#{i}.gz", { "file_#{i}.rb" => "spec/#{i}/" })
      end

      intermediates_dir = File.join(tmpdir, "intermediates")
      results = {}
      described_class.new(max_readers: 2, intermediates_dir: intermediates_dir).build(fragments) do |file, sp|
        results[file] = sp
      end

      expect(results.size).to eq(5)
      5.times { |i| expect(results["file_#{i}.rb"]).to eq(["spec/#{i}/"]) }
      # Intermediates should be cleaned up
      expect(Dir.exist?(intermediates_dir)).to be false
    end

    it "merges overlapping entries across intermediates" do
      fragments = 10.times.map do |i|
        write_fragment(tmpdir, "f#{i}.gz", { "shared.rb" => "spec/#{i}/" })
      end

      results = {}
      described_class.new(max_readers: 3, intermediates_dir: File.join(tmpdir, "intermediates")).build(fragments) do |file, sp|
        results[file] = sp
      end

      expect(results["shared.rb"].size).to eq(10)
    end
  end

  private

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
