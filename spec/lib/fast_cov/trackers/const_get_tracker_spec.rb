# frozen_string_literal: true

require "fast_cov/trackers/const_get_tracker"

RSpec.describe FastCov::ConstGetTracker do
  let(:service_file) { fixtures_path("const_get", "service.rb") }
  let(:mailer_file) { fixtures_path("const_get", "mailer.rb") }

  before(:all) do
    require_relative "../../../fixtures/const_get/service"
    require_relative "../../../fixtures/const_get/mailer"
  end

  before do
    FastCov::ConstGetTracker.reset
  end

  let(:config) do
    double("config",
      root: fixtures_path("const_get"),
      ignored_path: nil,
      threads: true
    )
  end

  subject(:tracker) { described_class.new(config) }

  describe "#install" do
    it "patches Module with ConstGetPatch" do
      tracker.install

      expect(Module.ancestors).to include(FastCov::ConstGetTracker::ConstGetPatch)
    end
  end

  describe "#start and #stop" do
    before { tracker.install }

    it "records const source location when const_get is called" do
      tracker.start
      ConstGetFixtures.const_get(:Service)
      result = tracker.stop

      expect(result).to include(service_file)
    end

    it "records const source location with string name" do
      tracker.start
      ConstGetFixtures.const_get("Service")
      result = tracker.stop

      expect(result).to include(service_file)
    end

    it "records from nested const_get calls" do
      tracker.start
      Object.const_get("ConstGetFixtures::Mailer")
      result = tracker.stop

      expect(result).to include(mailer_file)
    end

    it "records multiple constants" do
      tracker.start
      ConstGetFixtures.const_get(:Service)
      ConstGetFixtures.const_get(:Mailer)
      result = tracker.stop

      expect(result).to include(service_file)
      expect(result).to include(mailer_file)
    end

    it "returns empty set when no const_get calls are made" do
      tracker.start
      result = tracker.stop

      expect(result).to be_empty
    end

    it "does not record when tracker is not started" do
      tracker.install
      ConstGetFixtures.const_get(:Service)
      tracker.start
      result = tracker.stop

      expect(result).to be_empty
    end

    it "handles non-existent constants gracefully" do
      tracker.start
      begin
        ConstGetFixtures.const_get(:NonExistent)
      rescue NameError
        # expected
      end
      result = tracker.stop

      expect(result).to be_empty
    end

    it "handles constants without source location (C-defined)" do
      tracker.start
      Object.const_get(:String)
      result = tracker.stop

      # String is C-defined, so no source location
      expect(result).to be_empty
    end
  end

  describe "root filtering" do
    it "only records files within root" do
      other_root_config = double("config",
        root: "/some/other/path",
        ignored_path: nil,
        threads: true
      )
      tracker = described_class.new(other_root_config)
      tracker.install

      tracker.start
      ConstGetFixtures.const_get(:Service)
      result = tracker.stop

      expect(result).to be_empty
    end
  end

  describe "ignored_path filtering" do
    it "excludes files under ignored_path" do
      ignored_config = double("config",
        root: fixtures_path,
        ignored_path: fixtures_path("const_get"),
        threads: true
      )
      tracker = described_class.new(ignored_config)
      tracker.install

      tracker.start
      ConstGetFixtures.const_get(:Service)
      result = tracker.stop

      expect(result).to be_empty
    end
  end

  describe "threading behavior" do
    context "with threads: true (global tracking)" do
      let(:config) do
        double("config",
          root: fixtures_path("const_get"),
          ignored_path: nil,
          threads: true
        )
      end

      it "records const_get from any thread" do
        tracker.install
        tracker.start

        thread = Thread.new { ConstGetFixtures.const_get(:Service) }
        thread.join

        result = tracker.stop
        expect(result).to include(service_file)
      end
    end

    context "with threads: false (single-thread tracking)" do
      let(:config) do
        double("config",
          root: fixtures_path("const_get"),
          ignored_path: nil,
          threads: false
        )
      end

      it "only records const_get from the starting thread" do
        tracker.install
        tracker.start

        thread = Thread.new { ConstGetFixtures.const_get(:Service) }
        thread.join

        result = tracker.stop
        expect(result).to be_empty
      end

      it "records const_get from the starting thread" do
        tracker.install
        tracker.start
        ConstGetFixtures.const_get(:Service)
        result = tracker.stop

        expect(result).to include(service_file)
      end
    end
  end
end
