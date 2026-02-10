# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks FactoryBot factory definition files when factories are used.
  #
  # Factory files are typically loaded at boot time, before coverage starts.
  # This tracker intercepts FactoryBot.factories.find (called by create/build)
  # to record the source file where each factory was defined.
  #
  # Register via: config.use FastCov::FactoryBotTracker
  # Options: root, ignored_path, threads (all default from config)
  class FactoryBotTracker < AbstractTracker
    def install
      unless defined?(::FactoryBot)
        raise LoadError, "FactoryBotTracker requires the factory_bot gem to be installed"
      end

      ::FactoryBot.factories.singleton_class.prepend(RegistryPatch)
    end

    module RegistryPatch
      def find(name)
        factory = super
        FastCov::FactoryBotTracker.record_factory_files(factory)
        factory
      end
    end

    class << self
      def record_factory_files(factory)
        return unless active

        definition = factory.definition
        declarations = definition.instance_variable_get(:@declarations)
        return unless declarations

        declarations.each do |decl|
          block = decl.instance_variable_get(:@block)
          next unless block.is_a?(Proc)

          location = block.source_location
          next unless location

          record(location[0])
        end
      end
    end
  end
end
