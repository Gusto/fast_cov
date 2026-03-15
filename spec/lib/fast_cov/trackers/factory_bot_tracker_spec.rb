# frozen_string_literal: true

require "factory_bot"
require "fast_cov/trackers/factory_bot_tracker"

RSpec.describe FastCov::FactoryBotTracker do
  let(:factory_file) { fixtures_path("factory_bot", "factories.rb") }

  before(:all) do
    require_relative "../../../fixtures/factory_bot/factories"
  end

  before do
    FastCov::FactoryBotTracker.reset
  end

  let(:coverage_map) do
    instance_double(FastCov::CoverageMap, threads: true)
  end

  subject(:tracker) { described_class.new(coverage_map) }

  before do
    allow(coverage_map).to receive(:include_path?) do |path|
      path.start_with?(fixtures_path("factory_bot"))
    end
  end

  describe "#install" do
    it "patches FactoryBot.factories with RegistryPatch" do
      tracker.install

      expect(FactoryBot.factories.singleton_class.ancestors)
        .to include(FastCov::FactoryBotTracker::RegistryPatch)
    end
  end

  describe "#start and #stop" do
    before { tracker.install }

    it "records factory files when factories are used" do
      tracker.start
      FactoryBot.build(:user)
      result = tracker.stop

      expect(result).to include(factory_file)
    end

    it "records files from multiple factory usages" do
      tracker.start
      FactoryBot.build(:user)
      FactoryBot.build(:post)
      result = tracker.stop

      expect(result).to include(factory_file)
    end

    it "returns empty set when no factories are used" do
      tracker.start
      result = tracker.stop

      expect(result).to be_empty
    end

    it "does not record when tracker is not started" do
      tracker.install
      FactoryBot.build(:user)
      tracker.start
      result = tracker.stop

      expect(result).to be_empty
    end
  end

  describe "coverage map filtering" do
    it "only records files the coverage map includes" do
      allow(coverage_map).to receive(:include_path?).and_return(false)
      tracker.install

      tracker.start
      FactoryBot.build(:user)
      result = tracker.stop

      expect(result).to be_empty
    end
  end

  describe "threading behavior" do
    context "with threads: true (global tracking)" do
      it "records factory usage from any thread" do
        tracker.install
        tracker.start

        thread = Thread.new { FactoryBot.build(:user) }
        thread.join

        result = tracker.stop
        expect(result).to include(factory_file)
      end
    end

    context "with threads: false (single-thread tracking)" do
      let(:coverage_map) { instance_double(FastCov::CoverageMap, threads: false) }

      before do
        allow(coverage_map).to receive(:include_path?).and_return(true)
      end

      it "only records factory usage from the starting thread" do
        tracker.install
        tracker.start

        thread = Thread.new { FactoryBot.build(:user) }
        thread.join

        result = tracker.stop
        expect(result).to be_empty
      end

      it "records factory usage from the starting thread" do
        tracker.install
        tracker.start
        FactoryBot.build(:user)
        result = tracker.stop

        expect(result).to include(factory_file)
      end
    end
  end

  describe "when FactoryBot is not defined" do
    it "raises LoadError with helpful message" do
      factory_bot = Object.send(:remove_const, :FactoryBot)

      begin
        tracker = described_class.new(coverage_map)
        expect { tracker.install }.to raise_error(
          LoadError,
          /factory_bot gem/
        )
      ensure
        Object.const_set(:FactoryBot, factory_bot)
      end
    end
  end
end
