# frozen_string_literal: true

module FastCov
  # Tracks FactoryBot factory definition files when factories are used.
  #
  # Factory files are typically loaded at boot time, before coverage starts.
  # This tracker intercepts FactoryBot.factories.find (called by create/build)
  # to record the source file where each factory was defined.
  #
  # Register via: config.use FastCov::FactoryBotTracker
  # Options: root, ignored_path, threads (all default from config)
  #
  # Threading behavior (matches Coverage C extension):
  # - threads: true  -> track factory usage from ALL threads (global tracking)
  # - threads: false -> only track factory usage from the thread that called start
  class FactoryBotTracker
    def initialize(config, **options)
      @root = options.fetch(:root, config.root)
      @ignored_path = options.fetch(:ignored_path, config.ignored_path)
      @threads = options.fetch(:threads, config.threads)
      @files = nil
      @started_thread = nil
    end

    def install
      unless defined?(::FactoryBot)
        raise LoadError, "FactoryBotTracker requires the factory_bot gem to be installed"
      end

      ::FactoryBot.factories.singleton_class.prepend(RegistryPatch)
    end

    def start
      @files = {}
      @started_thread = Thread.current unless @threads
      self.class.active = self
    end

    def stop
      self.class.active = nil
      @started_thread = nil
      result = @files
      @files = nil
      result
    end

    def record(abs_path)
      return if !@threads && Thread.current != @started_thread
      return unless abs_path.start_with?(@root)
      return if @ignored_path && abs_path.start_with?(@ignored_path)

      @files[abs_path] = true
    end

    # -- Class-level: Registry patch + active tracker routing --

    @active = nil

    module RegistryPatch
      def find(name)
        factory = super
        FastCov::FactoryBotTracker.record_factory_files(factory)
        factory
      end
    end

    class << self
      attr_accessor :active

      def record_factory_files(factory)
        return unless @active

        # Extract source file from declaration blocks
        definition = factory.definition
        declarations = definition.instance_variable_get(:@declarations)
        return unless declarations

        declarations.each do |decl|
          block = decl.instance_variable_get(:@block)
          next unless block.is_a?(Proc)

          location = block.source_location
          next unless location

          file_path = location[0]
          @active.record(file_path)
        end
      end

      def reset
        @active = nil
      end
    end
  end
end
