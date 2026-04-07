# frozen_string_literal: true

require_relative "../../../fixtures/fixture_kit/models"
require_relative "../../../fixtures/fixture_kit/widget_builder"
require "fixture_kit/rspec"

FixtureKit.runner.configuration.fixture_path = "spec/fixtures/fixture_kit/definitions"

RSpec.describe FastCov::FixtureKitTracker do
  ROOT = File.expand_path("../../../..", __dir__)
  FIXTURE_FILE = File.join(ROOT, "spec/fixtures/fixture_kit/definitions/basic_widgets.rb")
  HELPER_FILE = File.join(ROOT, "spec/fixtures/fixture_kit/widget_helper.rb")
  BUILDER_FILE = File.join(ROOT, "spec/fixtures/fixture_kit/widget_builder.rb")

  describe "fixture generation tracking" do
    it "connects fixture file to source files it invokes during generation" do
      map = FastCov::CoverageMap.new
      map.root = ROOT
      map.use(FastCov::FixtureKitTracker)

      fixture_obj = FixtureKit.runner.registry.add("basic_widgets")
      fixture_obj.generate(force: true)

      connections = map.connected_dependencies.instance_variable_get(:@connections)

      expect(connections[FIXTURE_FILE]).to be_a(Hash)
      expect(connections[FIXTURE_FILE]).to have_key(HELPER_FILE)
    end
  end

  describe "end-to-end file fixture mount" do
    coverage_map = FastCov::CoverageMap.new
    coverage_map.root = ROOT
    coverage_map.use(FastCov::FixtureKitTracker)

    coverages = []

    formatter = Class.new do
      RSpec::Core::Formatters.register self, :example_started, :example_finished
      define_method(:initialize) { |_output| }
      define_method(:example_started) { |_| coverage_map.start }
      define_method(:example_finished) { |_| coverages << coverage_map.stop }
    end

    before(:all) { RSpec.configuration.add_formatter(formatter.new(StringIO.new)) }

    fixture "basic_widgets"

    it "test using file fixture" do
      expect(fixture.widget.name).to eq("Sprocket")
    end

    it "includes the fixture file and its dependencies in coverage" do
      expect(coverages.last).to include(
        "spec/fixtures/fixture_kit/definitions/basic_widgets.rb",
        "spec/fixtures/fixture_kit/widget_helper.rb"
      )
    end
  end

  describe "end-to-end inline fixture extending a file fixture" do
    coverage_map = FastCov::CoverageMap.new
    coverage_map.root = ROOT
    coverage_map.use(FastCov::FixtureKitTracker)

    coverages = []

    formatter = Class.new do
      RSpec::Core::Formatters.register self, :example_started, :example_finished
      define_method(:initialize) { |_output| }
      define_method(:example_started) { |_| coverage_map.start }
      define_method(:example_finished) { |_| coverages << coverage_map.stop }
    end

    before(:all) { RSpec.configuration.add_formatter(formatter.new(StringIO.new)) }

    fixture extends: "basic_widgets" do
      special = WidgetBuilder.build_special
      expose(special: special)
    end

    it "first test triggers inline fixture generation" do
      expect(fixture.special.name).to eq("Special")
    end

    it "second test mounts from cache without re-executing the block" do
      expect(fixture.special.name).to eq("Special")
    end

    it "both tests include the inline fixture's dependencies in coverage" do
      first_coverage = coverages[0]
      second_coverage = coverages[1]

      # Both tests should have the parent fixture file
      expect(first_coverage).to include("spec/fixtures/fixture_kit/definitions/basic_widgets.rb")
      expect(second_coverage).to include("spec/fixtures/fixture_kit/definitions/basic_widgets.rb")

      # Both tests should have the inline block's dependency (widget_builder.rb)
      expect(first_coverage).to include("spec/fixtures/fixture_kit/widget_builder.rb")
      expect(second_coverage).to include("spec/fixtures/fixture_kit/widget_builder.rb")
    end
  end
end
