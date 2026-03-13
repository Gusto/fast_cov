# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks files read from disk during coverage (JSON, YAML, .rb templates, etc.)
  # via File.read and File.open.
  #
  # Register via: config.use FastCov::FileTracker
  class FileTracker < AbstractTracker
    def install
      File.singleton_class.prepend(FilePatch)
    end

    module FilePatch
      def read(name, *args, **kwargs, &block)
        owner = caller_locations(1, 1).first&.absolute_path
        super.tap { FastCov::FileTracker.record(owner: owner) { File.expand_path(name) } }
      end

      def open(name, *args, **kwargs, &block)
        mode = args[0]
        is_read = mode.nil? || (mode.is_a?(String) && mode.start_with?("r")) ||
                  (mode.is_a?(Integer) && (mode & (File::WRONLY | File::RDWR)).zero?)
        owner = caller_locations(1, 1).first&.absolute_path
        super.tap do
          FastCov::FileTracker.record(owner: owner) { File.expand_path(name) } if is_read
        end
      end
    end
  end
end
