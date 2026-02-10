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
        super.tap { FastCov::FileTracker.record { File.expand_path(name) } }
      end

      def open(name, *args, **kwargs, &block)
        mode = args[0]
        is_read = mode.nil? || (mode.is_a?(String) && mode.start_with?("r")) ||
                  (mode.is_a?(Integer) && (mode & (File::WRONLY | File::RDWR)).zero?)
        super.tap { FastCov::FileTracker.record { File.expand_path(name) } if is_read }
      end
    end
  end
end
