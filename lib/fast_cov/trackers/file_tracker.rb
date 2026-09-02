# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks files read from disk during coverage (JSON, YAML, .rb templates, etc.)
  # via File.read, File.open, and YAML load methods.
  #
  # YAML methods are patched separately because Bootsnap's compile cache
  # overrides YAML.load_file/safe_load_file to bypass File.open entirely.
  #
  # Register via: coverage_map.use(FastCov::FileTracker)
  class FileTracker < AbstractTracker
    def install
      unless File.singleton_class.ancestors.include?(FilePatch)
        File.singleton_class.prepend(FilePatch)
      end

      if defined?(::YAML) && !::YAML.singleton_class.ancestors.include?(YamlPatch)
        ::YAML.singleton_class.prepend(YamlPatch)
      end
    end

    # The patches are permanent, so each checks active before doing any work.
    # Paths go over raw because AbstractTracker#record normalizes them.
    module FilePatch
      def read(name, *args, **kwargs, &block)
        super.tap do
          FastCov::FileTracker.record(name) if FastCov::FileTracker.active
        end
      end

      def open(name, *args, **kwargs, &block)
        super.tap do
          next unless FastCov::FileTracker.active

          mode = args[0]
          is_read = mode.nil? || (mode.is_a?(String) && mode.start_with?("r")) ||
                    (mode.is_a?(Integer) && (mode & (File::WRONLY | File::RDWR)).zero?)
          FastCov::FileTracker.record(name) if is_read
        end
      end
    end

    module YamlPatch
      def load_file(path, *args, **kwargs)
        super.tap do
          FastCov::FileTracker.record(path) if FastCov::FileTracker.active
        end
      end

      def safe_load_file(path, *args, **kwargs)
        super.tap do
          FastCov::FileTracker.record(path) if FastCov::FileTracker.active
        end
      end

      def unsafe_load_file(path, *args, **kwargs)
        super.tap do
          FastCov::FileTracker.record(path) if FastCov::FileTracker.active
        end
      end
    end
  end
end
