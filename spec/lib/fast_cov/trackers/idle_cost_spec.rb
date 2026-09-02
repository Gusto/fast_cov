# frozen_string_literal: true

# The tracker patches are permanent, so anything expensive has to sit behind
# the active check.
RSpec.describe "tracker cost while inactive" do
  let(:coverage_map) do
    FastCov::CoverageMap.new.tap do |coverage|
      coverage.root = fixtures_path("calculator")
      coverage.use(FastCov::FileTracker)
      coverage.use(FastCov::ConstGetTracker)
    end
  end

  before { coverage_map }

  describe "ConstGetTracker" do
    # ConstGetPatch resolves the constant's source location on the receiving
    # module, so a module that counts those calls reports whether the lookup
    # happened without stubbing anything.
    let(:namespace) do
      Module.new do
        const_set(:Thing, Class.new)

        class << self
          attr_reader :source_lookups

          def const_source_location(...)
            @source_lookups = source_lookups.to_i + 1
            super
          end
        end
      end
    end

    it "does not resolve the constant's source location while inactive" do
      namespace.const_get(:Thing)

      expect(namespace.source_lookups).to be_nil
    end

    it "resolves it while active" do
      coverage_map.start
      namespace.const_get(:Thing)

      expect(namespace.source_lookups).to eq(1)
    ensure
      coverage_map.stop
    end

    it "still returns the constant either way" do
      expect(namespace.const_get(:Thing)).to be(namespace::Thing)
    end
  end

  describe "FileTracker" do
    # File.read converts its argument via #to_path exactly once. Recording adds
    # a #to_s when the path is normalized, so the conversion count shows
    # whether the tracker touched the path at all.
    let(:path) do
      Class.new do
        attr_reader :conversions

        def initialize(path)
          @path = path
          @conversions = 0
        end

        def to_path
          @conversions += 1
          @path
        end
        alias_method :to_s, :to_path
      end.new(fixtures_path("calculator", "config.yml"))
    end

    it "does not convert the path beyond File.read's own lookup while inactive" do
      File.read(path)

      expect(path.conversions).to eq(1)
    end

    it "converts it again to normalize while active" do
      coverage_map.start
      File.read(path)

      expect(path.conversions).to eq(2)
    ensure
      coverage_map.stop
    end
  end

  describe "recording still works end to end" do
    it "records file reads and dynamic constant lookups" do
      result = coverage_map.build do
        File.read(fixtures_path("calculator", "config.yml"))
        Object.const_get("Calculator")
      end

      expect(result).to include("config.yml", "calculator.rb")
    end
  end
end
