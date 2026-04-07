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

    module FilePatch
      def read(name, *args, **kwargs, &block)
        super.tap do
          FastCov::FileTracker.record(File.expand_path(name))
        end
      end

      def open(name, *args, **kwargs, &block)
        mode = args[0]
        is_read = mode.nil? || (mode.is_a?(String) && mode.start_with?("r")) ||
                  (mode.is_a?(Integer) && (mode & (File::WRONLY | File::RDWR)).zero?)
        super.tap do
          FastCov::FileTracker.record(File.expand_path(name)) if is_read
        end
      end
    end

    module YamlPatch
      def load_file(path, *args, **kwargs)
        super.tap do
          FastCov::FileTracker.record(File.expand_path(path))
        end
      end

      def safe_load_file(path, *args, **kwargs)
        super.tap do
          FastCov::FileTracker.record(File.expand_path(path))
        end
      end

      def unsafe_load_file(path, *args, **kwargs)
        super.tap do
          FastCov::FileTracker.record(File.expand_path(path))
        end
      end
    end
  end
end
