# frozen_string_literal: true

require "yaml"

# The tracker patches stay installed for the life of the process, so anything
# expensive has to sit behind the active check. These specs assert the work is
# skipped while no session is running, rather than computed and discarded.
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
    it "does not resolve constant source locations while inactive" do
      allow(Object).to receive(:const_source_location).and_call_original

      Object.const_get("Calculator")

      expect(Object).not_to have_received(:const_source_location)
    end

    it "resolves them while active" do
      coverage_map.start
      allow(Object).to receive(:const_source_location).and_call_original

      Object.const_get("Calculator")

      expect(Object).to have_received(:const_source_location)
    ensure
      coverage_map.stop
    end
  end

  describe "FileTracker" do
    let(:path) { fixtures_path("calculator", "config.yml") }

    it "does not expand paths while inactive" do
      allow(File).to receive(:expand_path).and_call_original

      File.read(path)

      expect(File).not_to have_received(:expand_path)
    end

    it "does not expand paths for YAML loads while inactive" do
      allow(File).to receive(:expand_path).and_call_original

      YAML.unsafe_load_file(path)

      expect(File).not_to have_received(:expand_path)
    end

    it "expands them while active" do
      coverage_map.start
      allow(File).to receive(:expand_path).and_call_original

      File.read(path)

      expect(File).to have_received(:expand_path).with(path)
    ensure
      coverage_map.stop
    end
  end

  describe "recording still works end to end" do
    it "records both file reads and dynamic constant lookups" do
      result = coverage_map.build do
        File.read(fixtures_path("calculator", "config.yml"))
        Object.const_get("Calculator")
      end

      expect(result).to include("config.yml", "calculator.rb")
    end
  end
end
