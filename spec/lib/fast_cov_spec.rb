# frozen_string_literal: true

RSpec.describe FastCov do
  describe ".configured?" do
    it "is false before configure" do
      expect(FastCov.configured?).to be false
    end

    it "is true after configure" do
      FastCov.configure do |c|
        c.root = fixtures_path("calculator")
        c.use FastCov::CoverageTracker
      end
      expect(FastCov.configured?).to be true
    end
  end

  describe ".start / .stop" do
    it "raises without configure" do
      expect { FastCov.start }.to raise_error(RuntimeError, /configure/)
    end

    it "raises stop without configure" do
      expect { FastCov.stop }.to raise_error(RuntimeError, /configure/)
    end

    it "tracks line coverage" do
      FastCov.configure do |c|
        c.root = fixtures_path("calculator/operations")
        c.use FastCov::CoverageTracker
      end
      FastCov.start
      Calculator.new.add(1, 2)
      result = FastCov.stop

      expect(result.keys).to include("add.rb")
    end

    it "returns self from start" do
      FastCov.configure do |c|
        c.root = fixtures_path("calculator")
        c.use FastCov::CoverageTracker
      end
      expect(FastCov.start).to be(FastCov)
    end
  end

  describe "block form" do
    it "returns the coverage hash" do
      FastCov.configure do |c|
        c.root = fixtures_path("calculator/operations")
        c.use FastCov::CoverageTracker
      end
      result = FastCov.start do
        Calculator.new.add(1, 2)
        Calculator.new.subtract(3, 1)
      end

      expect(result).to be_a(Hash)
      expect(result.keys).to include("add.rb", "subtract.rb")
    end
  end

  describe ".reset" do
    it "clears configured state" do
      FastCov.configure do |c|
        c.root = Dir.pwd
        c.use FastCov::CoverageTracker
      end
      expect(FastCov.configured?).to be true
      FastCov.reset
      expect(FastCov.configured?).to be false
    end

    it "allows reconfiguration after reset" do
      FastCov.configure do |c|
        c.root = "/first"
        c.use FastCov::CoverageTracker
      end
      FastCov.reset

      root_seen = nil
      FastCov.configure do |c|
        root_seen = c.root
        c.use FastCov::CoverageTracker
      end
      expect(root_seen).to eq(Dir.pwd)
    end
  end

  describe "config.use" do
    it "registers a tracker that receives config and options" do
      FastCov.configure do |config|
        config.root = fixtures_path("calculator")
        config.use FastCov::CoverageTracker
        config.use FastCov::FileTracker
      end

      coverage = FastCov.start do
        File.read(fixtures_path("calculator", "config.yml"))
      end

      expect(coverage.keys).to include("config.yml")
    end

    it "passes options to the tracker" do
      FastCov.configure do |config|
        config.root = fixtures_path("calculator")
        config.use FastCov::CoverageTracker
        config.use FastCov::FileTracker, root: fixtures_path("calculator", "operations")
      end

      FastCov.start
      File.read(fixtures_path("calculator", "config.yml"))
      File.read(fixtures_path("calculator", "operations", "ops_config.yml"))
      coverage = FastCov.stop

      expect(coverage.keys).not_to include("config.yml")
      expect(coverage.keys).to include("operations/ops_config.yml")
    end
  end
end
