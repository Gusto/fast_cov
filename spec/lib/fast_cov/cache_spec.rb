# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe FastCov::Cache do
  let(:cache_dir) { File.join(Dir.tmpdir, "fast_cov_test_cache_#{Process.pid}") }

  let(:cov) do
    FastCov::Coverage.new(
      root: fixtures_path("calculator"),
      threading_mode: :multi
    )
  end

  after do
    FastCov::Cache.clear
    FastCov.configuration.reset
    FileUtils.rm_rf(cache_dir) if File.directory?(cache_dir)
  end

  describe "disk persistence round-trip" do
    it "saves cache to disk and restores it after clearing" do
      cov.start
      ConstantReader.new.operations
      cov.stop

      FastCov::Cache.save(cache_dir)
      FastCov::Cache.clear

      FastCov::Cache.load(cache_dir)

      # Verify the restored cache still produces correct coverage
      cov.start
      ConstantReader.new.operations
      result = cov.stop

      expect(result.keys).to include(
        fixtures_path("calculator/operations/constant_reader.rb"),
        fixtures_path("calculator/constants.rb")
      )
    end
  end

  describe ".clear" do
    it "resets the cache so subsequent runs recompute from scratch" do
      cov.start
      ConstantReader.new.operations
      cov.stop

      FastCov::Cache.clear

      # After clear, cache should report as not loaded
      expect(FastCov::Cache.loaded?).to be false
      # Data should be empty
      expect(FastCov::Cache.data["const_refs"]).to be_empty
    end
  end

  describe ".loaded?" do
    it "is false initially and true after loading from disk" do
      expect(FastCov::Cache.loaded?).to be false

      cov.start
      cov.stop
      FastCov::Cache.save(cache_dir)
      FastCov::Cache.clear

      FastCov::Cache.load(cache_dir)
      expect(FastCov::Cache.loaded?).to be true
    end
  end

  describe "loading a corrupt cache file" do
    it "returns false and leaves the cache empty" do
      FileUtils.mkdir_p(cache_dir)
      File.binwrite(
        File.join(cache_dir, FastCov::Cache::CACHE_FILENAME),
        "corrupt data"
      )

      expect(FastCov::Cache.load(cache_dir)).to be false
      expect(FastCov::Cache.data["const_refs"]).to be_empty
    end
  end

  describe "loading a cache with a version mismatch" do
    it "returns false and ignores the stale data" do
      FileUtils.mkdir_p(cache_dir)
      payload = { "version" => 999, "data" => { "const_refs" => { "stale" => {} } } }
      File.binwrite(
        File.join(cache_dir, FastCov::Cache::CACHE_FILENAME),
        Marshal.dump(payload)
      )

      expect(FastCov::Cache.load(cache_dir)).to be false
      expect(FastCov::Cache.data["const_refs"]).to be_empty
    end
  end

  describe ".save and .load with nil path" do
    it "returns false for both" do
      expect(FastCov::Cache.save(nil)).to be false
      expect(FastCov::Cache.load(nil)).to be false
    end
  end

  describe ".data=" do
    it "raises TypeError for non-Hash input" do
      expect { FastCov::Cache.data = "bad" }.to raise_error(TypeError)
    end
  end
end
