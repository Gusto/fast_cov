# frozen_string_literal: true

require "factory_bot"
require "fast_cov/trackers/factory_bot_tracker"

RSpec.describe FastCov::FactoryBotTracker do
  let(:factory_file) { fixtures_path("factory_bot", "factories.rb") }

  before(:all) do
    # Load our test factories once
    require_relative "../../../fixtures/factory_bot/factories"
  end

  before do
    FastCov::FactoryBotTracker.reset
  end

  let(:config) do
    double("config",
      root: fixtures_path("factory_bot"),
      ignored_path: nil,
      threads: true
    )
  end

  subject(:tracker) { described_class.new(config) }

  describe "#install" do
    it "patches FactoryBot.factories with RegistryPatch" do
      tracker.install

      expect(FactoryBot.factories.singleton_class.ancestors)
        .to include(FastCov::FactoryBotTracker::RegistryPatch)
    end

    it "is idempotent" do
      tracker.install
      tracker.install

      patches = FactoryBot.factories.singleton_class.ancestors
        .count { |a| a == FastCov::FactoryBotTracker::RegistryPatch }

      expect(patches).to eq(1)
    end
  end

  describe "#start and #stop" do
    before { tracker.install }

    it "records factory files when factories are used" do
      tracker.start
      FactoryBot.build(:user)
      result = tracker.stop

      expect(result).to have_key(factory_file)
    end

    it "records files from multiple factory usages" do
      tracker.start
      FactoryBot.build(:user)
      FactoryBot.build(:post)
      result = tracker.stop

      expect(result).to have_key(factory_file)
    end

    it "returns empty hash when no factories are used" do
      tracker.start
      result = tracker.stop

      expect(result).to eq({})
    end

    it "does not record when tracker is not started" do
      tracker.install
      FactoryBot.build(:user)
      tracker.start
      result = tracker.stop

      expect(result).to eq({})
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
      FactoryBot.build(:user)
      result = tracker.stop

      expect(result).to be_empty
    end
  end

  describe "ignored_path filtering" do
    it "excludes files under ignored_path" do
      ignored_config = double("config",
        root: fixtures_path,
        ignored_path: fixtures_path("factory_bot"),
        threads: true
      )
      tracker = described_class.new(ignored_config)
      tracker.install

      tracker.start
      FactoryBot.build(:user)
      result = tracker.stop

      expect(result).to be_empty
    end
  end

  describe "threading behavior" do
    context "with threads: true (global tracking)" do
      let(:config) do
        double("config",
          root: fixtures_path("factory_bot"),
          ignored_path: nil,
          threads: true
        )
      end

      it "records factory usage from any thread" do
        tracker.install
        tracker.start

        thread = Thread.new { FactoryBot.build(:user) }
        thread.join

        result = tracker.stop
        expect(result).to have_key(factory_file)
      end
    end

    context "with threads: false (single-thread tracking)" do
      let(:config) do
        double("config",
          root: fixtures_path("factory_bot"),
          ignored_path: nil,
          threads: false
        )
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

        expect(result).to have_key(factory_file)
      end
    end
  end

  describe "when FactoryBot is not defined" do
    it "install does nothing gracefully" do
      # Temporarily hide FactoryBot
      factory_bot = Object.send(:remove_const, :FactoryBot)

      begin
        tracker = described_class.new(config)
        expect { tracker.install }.not_to raise_error
      ensure
        Object.const_set(:FactoryBot, factory_bot)
      end
    end
  end
end
