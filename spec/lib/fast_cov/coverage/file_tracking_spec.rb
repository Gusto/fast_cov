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

    it "tracks files read via File.binread" do
      coverage_map.start
      File.binread(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via File.new" do
      coverage_map.start
      File.new(fixtures_path("calculator", "config.yml")).close
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via File.readlines" do
      coverage_map.start
      File.readlines(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via File.foreach" do
      coverage_map.start
      File.foreach(fixtures_path("calculator", "config.yml")) { |_line| nil }
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via IO.read" do
      coverage_map.start
      IO.read(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via IO.binread" do
      coverage_map.start
      IO.binread(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via IO.readlines" do
      coverage_map.start
      IO.readlines(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via IO.foreach" do
      coverage_map.start
      IO.foreach(fixtures_path("calculator", "config.yml")) { |_line| nil }
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "records a File.read once, though File inherits the IO patch" do
      allow(FastCov::FileTracker).to receive(:record).and_call_original

      coverage_map.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage_map.stop

      expect(FastCov::FileTracker).to have_received(:record).once
    end

    it "tracks YAML files loaded via YAML.safe_load_file" do
      coverage_map.start
      YAML.safe_load_file(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks YAML files loaded via YAML.load_file" do
      coverage_map.start
      YAML.load_file(fixtures_path("calculator", "config.yml"), permitted_classes: [Symbol])
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks YAML files loaded via YAML.unsafe_load_file" do
      coverage_map.start
      YAML.unsafe_load_file(fixtures_path("calculator", "config.yml"))
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
    end

    it "does not track YAML files outside root" do
      coverage_map.start
      YAML.safe_load_file(File.expand_path("../../spec_helper.rb", __dir__)) rescue nil
      coverage = coverage_map.stop

      expect(coverage.any? { |k| k.end_with?("spec_helper.rb") }).to be false
    end

    it "does not track YAML files that fail to load" do
      coverage_map.start
      begin
        YAML.safe_load_file(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "creates connected dependency when code reads YAML indirectly" do
      coverage_map.start
      ConfigReader.read_yaml_config
      coverage = coverage_map.stop

      expect(coverage).to include("config.yml")
      expect(coverage).to include("operations/config_reader.rb")
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

    it "does not track files that fail to read via File.binread" do
      coverage_map.start
      begin
        File.binread(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via File.new" do
      coverage_map.start
      begin
        File.new(fixtures_path("calculator", "nonexistent.yml")).close
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via File.readlines" do
      coverage_map.start
      begin
        File.readlines(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via File.foreach" do
      coverage_map.start
      begin
        File.foreach(fixtures_path("calculator", "nonexistent.yml")) { |_line| nil }
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via IO.read" do
      coverage_map.start
      begin
        IO.read(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via IO.binread" do
      coverage_map.start
      begin
        IO.binread(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via IO.readlines" do
      coverage_map.start
      begin
        IO.readlines(fixtures_path("calculator", "nonexistent.yml"))
      rescue Errno::ENOENT
        # expected
      end
      coverage = coverage_map.stop

      expect(coverage).not_to include("nonexistent.yml")
    end

    it "does not track files that fail to read via IO.foreach" do
      coverage_map.start
      begin
        IO.foreach(fixtures_path("calculator", "nonexistent.yml")) { |_line| nil }
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

    it "does not track write operations via File.new" do
      coverage_map.start
      File.new(fixtures_path("calculator", "tmp_write_test.txt"), "w").close
      coverage = coverage_map.stop

      expect(coverage).not_to include("tmp_write_test.txt")
    ensure
      FileUtils.rm_f(fixtures_path("calculator", "tmp_write_test.txt"))
    end

    it "works with block form" do
      coverage = coverage_map.build do
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
