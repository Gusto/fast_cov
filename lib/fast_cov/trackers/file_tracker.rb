# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks files read from disk during coverage (JSON, YAML, .rb templates, etc.)
  # via File.read and File.open.
  #
  # Register via: config.use FastCov::FileTracker
  # Options: root, ignored_path, threads (all default from config)
  class FileTracker < AbstractTracker
    def install
      File.singleton_class.prepend(FilePatch)
    end

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
    end
  end
end
