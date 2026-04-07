# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks FixtureKit fixture definition files when fixtures are used.
  #
  # Fixture definitions run once during cache generation (before(:context)),
  # then every test replays cached SQL without executing Ruby. This tracker
  # uses FixtureKit's callback hooks to:
  #
  # 1. Connect the fixture file to all source files touched during generation
  # 2. Record the fixture definition file when a test mounts a fixture
  #
  # Requires fixture_kit >= 0.14.0 (Event-based callbacks).
  #
  # Register via: coverage_map.use(FastCov::FixtureKitTracker)
  class FixtureKitTracker < AbstractTracker
    def install
      gem "fixture_kit", ">= 0.14.0"

      tracker = self

      FixtureKit.configure do |config|
        # When a fixture is about to be generated, start the coverage map
        # to track what files the fixture definition touches.
        # This runs in before(:context), before the formatter starts coverage.
        config.on_cache_save do |_fixture|
          tracker.coverage_map.start
        end

        # After generation, stop coverage and connect the fixture file
        # to everything it touched.
        config.on_cache_saved do |fixture, _duration|
          files = tracker.coverage_map.stop
          files.each do |file|
            tracker.coverage_map.connect(from: fixture.path, to: file)
          end
        end

        # When a test mounts a fixture, record the fixture definition file
        # and any parent fixture files in the chain.
        config.on_cache_mount do |event|
          tracker.class.record(event.path)
          parent = event.fixture.parent
          while parent
            tracker.class.record(parent.definition.path)
            parent = parent.parent
          end
        end
      end
    end
  end
end
