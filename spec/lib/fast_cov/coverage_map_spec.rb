# frozen_string_literal: true

RSpec.describe FastCov::CoverageMap do
  let!(:calculator) { Calculator.new }

  describe "#start / #stop" do
    it "tracks line coverage by default" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator/operations")

      coverage.start
      calculator.add(1, 2)
      result = coverage.stop

      expect(result).to include("add.rb")
    end

    it "returns self from start without a block" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator")

      expect(coverage.start).to be(coverage)
      coverage.stop
    end

    it "returns a Set from block form" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator/operations")

      result = coverage.start do
        calculator.add(1, 2)
        calculator.subtract(3, 1)
      end

      expect(result).to be_a(Set)
      expect(result).to include("add.rb", "subtract.rb")
    end

    it "returns an empty set when stopped without being started" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator")

      expect(coverage.stop).to eq(Set.new)
    end

    it "is sequentially reusable across runs" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator/operations")

      coverage.start
      calculator.add(1, 2)
      first_result = coverage.stop

      coverage.start
      calculator.subtract(3, 1)
      second_result = coverage.stop

      expect(first_result).to include("add.rb")
      expect(first_result).not_to include("subtract.rb")
      expect(second_result).to include("subtract.rb")
      expect(second_result).not_to include("add.rb")
    end

    it "raises when block form is used while already started" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator")
      coverage.start

      expect { coverage.start {} }.to raise_error(RuntimeError, "CoverageMap is already started")
    ensure
      coverage.stop
    end
  end

  describe "#use" do
    it "registers extra trackers and merges their results" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator")
      coverage.use(FastCov::FileTracker)

      result = coverage.start do
        File.read(fixtures_path("calculator", "config.yml"))
      end

      expect(result).to include("config.yml")
    end

    it "passes tracker-specific options to custom trackers" do
      tracker_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(_coverage_map, **options)
          self.class.last_options = options
        end

        def install; end
        def start; end
        def stop = Set.new
      end

      coverage = described_class.new
      coverage.use(tracker_class, answer: 42)

      expect(tracker_class.last_options).to eq(answer: 42)
    end

    it "does not allow the same tracker class twice" do
      coverage = described_class.new
      coverage.use(FastCov::FileTracker)

      expect { coverage.use(FastCov::FileTracker) }.to raise_error(
        ArgumentError,
        /already registered/
      )
    end
  end

  describe "configuration" do
    it "accepts an absolute root String" do
      coverage = described_class.new
      coverage.root = "/app"

      expect(coverage.root).to eq("/app")
    end

    it "converts Pathname roots to String" do
      coverage = described_class.new
      coverage.root = Pathname.new("/app")

      expect(coverage.root).to eq("/app")
      expect(coverage.root).to be_a(String)
    end

    it "raises on relative root paths" do
      coverage = described_class.new

      expect { coverage.root = "app" }.to raise_error(
        FastCov::CoverageMap::ConfigurationError,
        /root must be an absolute path/
      )
    end

    it "raises when started without a root" do
      coverage = described_class.new
      coverage.root = nil

      expect { coverage.start }.to raise_error(
        FastCov::CoverageMap::ConfigurationError,
        "root is required"
      )
    end

    it "supports multiple ignored_paths" do
      coverage = described_class.new
      coverage.root = fixtures_path("calculator")
      coverage.ignored_paths << "operations"
      coverage.ignored_paths << fixtures_path("calculator/helpers")

      result = coverage.start do
        calculator.add(1, 2)
      end

      expect(result).not_to include("operations/add.rb")
    end

    it "wraps a single String ignored_paths value in an array" do
      coverage = described_class.new
      coverage.ignored_paths = "vendor"

      expect(coverage.ignored_paths).to eq(["vendor"])
    end

    it "wraps a single Pathname ignored_paths value in an array" do
      coverage = described_class.new
      coverage.ignored_paths = Pathname.new("vendor")

      expect(coverage.ignored_paths).to eq([Pathname.new("vendor")])
    end

    it "preserves array ignored_paths values" do
      coverage = described_class.new
      coverage.ignored_paths = ["vendor", Pathname.new("tmp")]

      expect(coverage.ignored_paths).to eq(["vendor", Pathname.new("tmp")])
    end

    it "raises when an ignored path is outside root" do
      coverage = described_class.new
      coverage.root = "/app"
      coverage.ignored_paths << "/other/vendor"

      expect { coverage.start }.to raise_error(
        FastCov::CoverageMap::ConfigurationError,
        /ignored_paths must be inside root/
      )
    end

  end
end
