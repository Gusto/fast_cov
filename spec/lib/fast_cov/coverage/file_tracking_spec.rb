# frozen_string_literal: true

require "yaml"
require "fileutils"

RSpec.describe "FastCov file tracking" do
  let(:root) { fixtures_path("calculator") }
  let!(:calculator) { Calculator.new }

  context "when enabled" do
    before do
      FastCov.configure do |config|
        config.root = root
        config.use FastCov::CoverageTracker
        config.use FastCov::FileTracker
      end
    end

    it "tracks files read via File.read" do
      FastCov.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = FastCov.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read via File.open" do
      FastCov.start
      File.open(fixtures_path("calculator", "config.yml"), "r") { |f| f.read }
      coverage = FastCov.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks YAML files loaded via YAML.safe_load_file" do
      FastCov.start
      YAML.safe_load_file(fixtures_path("calculator", "config.yml"))
      coverage = FastCov.stop

      expect(coverage).to include("config.yml")
    end

    it "tracks files read by executed Ruby code" do
      FastCov.start
      ConfigReader.read_config
      coverage = FastCov.stop

      expect(coverage).to include("config.yml")
    end

    it "does not track files outside the root" do
      FastCov.start
      File.read(File.expand_path("../../spec_helper.rb", __dir__)) rescue nil
      coverage = FastCov.stop

      expect(coverage.any? { |k| k.end_with?("spec_helper.rb") }).to be false
    end

    it "does not track write operations via File.open" do
      FastCov.start
      File.open(fixtures_path("calculator", "tmp_write_test.txt"), "w") { |f| f.write("test") }
      coverage = FastCov.stop

      expect(coverage).not_to include("tmp_write_test.txt")
    ensure
      FileUtils.rm_f(fixtures_path("calculator", "tmp_write_test.txt"))
    end

    it "works with block form" do
      coverage = FastCov.start do
        File.read(fixtures_path("calculator", "config.yml"))
      end

      expect(coverage).to include("config.yml")
    end

    it "tracks .rb files read via File.read (not just executed ones)" do
      FastCov.start
      File.read(fixtures_path("calculator", "constants.rb"))
      coverage = FastCov.stop

      expect(coverage).to include("constants.rb")
    end

    it "includes both line coverage and file reads in results" do
      FastCov.start
      calculator.add(1, 2)
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = FastCov.stop

      expect(coverage).to include("operations/add.rb", "config.yml")
    end
  end

  context "when enabled with ignored_path override" do
    before do
      FastCov.configure do |config|
        config.root = root
        config.use FastCov::CoverageTracker
        config.use FastCov::FileTracker, ignored_path: fixtures_path("calculator", "operations")
      end
    end

    it "does not track file reads in the ignored path" do
      FastCov.start
      File.read(fixtures_path("calculator", "operations", "ops_config.yml"))
      coverage = FastCov.stop

      expect(coverage).not_to include("operations/ops_config.yml")
    end

    it "still tracks file reads outside the ignored path" do
      FastCov.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = FastCov.stop

      expect(coverage).to include("config.yml")
    end
  end

  context "when not registered" do
    before do
      FastCov.configure do |config|
        config.root = root
        config.use FastCov::CoverageTracker
      end
    end

    it "does not track file reads" do
      FastCov.start
      File.read(fixtures_path("calculator", "config.yml"))
      coverage = FastCov.stop

      expect(coverage).not_to include("config.yml")
    end
  end
end
