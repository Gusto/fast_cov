# frozen_string_literal: true

require "yaml"
require "fileutils"

RSpec.describe "FastCov file tracking" do
  let(:root) { fixtures_path("calculator") }
  let!(:calculator) { Calculator.new }
  let(:coverage_map) do
    FastCov::CoverageMap.new.tap do |coverage|
      coverage.root = root
    end
  end

  context "when enabled" do
    before do
      coverage_map.use(FastCov::FileTracker)
    end

    it "tracks files read via File.read" do
      coverage_map.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via File.open" do
      coverage_map.start
      File.open(fixtures_path("calculator", "config.yml"), "r") { |f| f.read }
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks YAML files loaded via YAML.safe_load_file" do
      coverage_map.start
      YAML.safe_load_file(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read by executed Ruby code" do
      coverage_map.start
      ConfigReader.read_config
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "does not track files outside the root" do
      coverage_map.start
      File.read(File.expand_path("../../spec_helper.rb", __dir__)) rescue nil
      coverage = coverage_map.stop

      expect(coverage.any? { |k| k.end_with?("spec_helper.rb") }).to be false
    end

    it "does not track files that fail to read" do
      coverage_map.start
      begin
        File.read(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to open" do
      coverage_map.start
      begin
        File.open(fixtures_path("calculator", "nonexistent.yml"), "r") { |f| f.read }
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track write operations via File.open" do
      coverage_map.start
      File.open(fixtures_path("calculator", "tmp_write_test.txt"), "w") { |f| f.write("test") }
      coverage = coverage_map.stop

      expect(coverage).not_to include("tmp_write_test.txt")
    ensure
      FileUtils.rm_f(fixtures_path("calculator", "tmp_write_test.txt"))
    end

    it "works with block form" do
      coverage = coverage_map.start do
        File.read(fixtures_path("calculator", "config.yml"))
      end

      expect(coverage).to include("config.yml")
    end

    it "tracks .rb files read via File.read (not just executed ones)" do
      coverage_map.start
      File.read(fixtures_path("calculator", "constants.rb"))
      coverage = coverage_map.stop

      expect(coverage).to include("constants.rb")
    end

    it "includes both line coverage and file reads in results" do
      coverage_map.start
      calculator.add(1, 2)
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("operations/add.rb", "config.yml")
    end
  end

  context "when enabled with ignored_paths" do
    before do
      coverage_map.ignored_paths << fixtures_path("calculator", "operations")
      coverage_map.use(FastCov::FileTracker)
    end

    it "does not track file reads in the ignored path" do
      coverage_map.start
      File.read(fixtures_path("calculator", "operations", "ops_config.yml"))
      coverage = coverage_map.stop

      expect(coverage).not_to include("operations/ops_config.yml")
    end

    it "still tracks file reads outside the ignored path" do
      coverage_map.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end
  end

  context "when not registered" do
    it "does not track file reads" do
      coverage_map.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).not_to include("config.yml")
    end
  end
end
