# frozen_string_literal: true

module FastCov
  # Tracks files read from disk during coverage (JSON, YAML, .rb templates, etc.)
  # via File.read and File.open.
  #
  # Register via: config.use FastCov::FileTracker
  # Options: root (default: config.root), ignored_path (default: config.ignored_path)
  class FileTracker
    def initialize(config, **options)
      @root = options.fetch(:root, config.root)
      @ignored_path = options.fetch(:ignored_path, config.ignored_path)
      @files = {}
    end

    def install
      self.class.install_file_patch
    end

    def start
      self.class.active = self
    end

    def stop
      self.class.active = nil
      result = @files.dup
      @files.clear
      result
    end

    def record(abs_path)
      return unless abs_path.start_with?(@root)
      return if @ignored_path && abs_path.start_with?(@ignored_path)
      @files[abs_path] = true
    end

    # -- Class-level: File patch + active tracker routing --

    @active = nil
    @installed = false

    module FilePatch
      def read(name, *args, **kwargs, &block)
        FastCov::FileTracker.record_for_active(name)
        super
      end

      def open(name, *args, **kwargs, &block)
        mode = args[0]
        is_read = mode.nil? || (mode.is_a?(String) && mode.start_with?("r")) ||
                  (mode.is_a?(Integer) && (mode & (File::WRONLY | File::RDWR)).zero?)
        FastCov::FileTracker.record_for_active(name) if is_read
        super
      end
    end

    class << self
      attr_accessor :active

      def install_file_patch
        return if @installed
        File.singleton_class.prepend(FilePatch)
        @installed = true
      end

      def record_for_active(path)
        return unless @active

        path_str = path.to_s
        return if path_str.empty?

        abs_path = begin
          File.expand_path(path_str)
        rescue ArgumentError, TypeError
          return
        end

        @active.record(abs_path)
      end

      def reset
        @active = nil
      end
    end
  end
end
