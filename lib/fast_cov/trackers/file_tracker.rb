# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks files read from disk during coverage (JSON, YAML, .rb templates, etc.)
  # via the IO read methods (read, binread, readlines, foreach), read-mode
  # File.open and File.new, and YAML load methods.
  #
  # The IO methods are patched on IO itself, and File inherits them, so
  # File.read and IO.read share one patch and a read is recorded once.
  #
  # YAML methods are patched separately because Bootsnap's compile cache
  # overrides YAML.load_file/safe_load_file to bypass File.open entirely.
  #
  # Register via: coverage_map.use(FastCov::FileTracker)
  class FileTracker < AbstractTracker
    def install
      unless IO.singleton_class.ancestors.include?(IoPatch)
        IO.singleton_class.prepend(IoPatch)
      end

      unless File.singleton_class.ancestors.include?(FilePatch)
        File.singleton_class.prepend(FilePatch)
      end

      if defined?(::YAML) && !::YAML.singleton_class.ancestors.include?(YamlPatch)
        ::YAML.singleton_class.prepend(YamlPatch)
      end
    end

    def self.read_mode?(mode)
      mode.nil? || (mode.is_a?(String) && mode.start_with?("r")) ||
        (mode.is_a?(Integer) && (mode & (File::WRONLY | File::RDWR)).zero?)
    end

    # The patches are permanent, so each checks active before doing any work.
    # Paths go over raw because AbstractTracker#record normalizes them.
    # Patches that need only the path forward the rest with ... to skip the splat allocations.
    module IoPatch
      def read(name, ...)
        result = super
        FastCov::FileTracker.record(name) if FastCov::FileTracker.active
        result
      end

      def binread(name, ...)
        result = super
        FastCov::FileTracker.record(name) if FastCov::FileTracker.active
        result
      end

      def readlines(name, ...)
        result = super
        FastCov::FileTracker.record(name) if FastCov::FileTracker.active
        result
      end

      def foreach(name, ...)
        result = super
        FastCov::FileTracker.record(name) if FastCov::FileTracker.active
        result
      end
    end

    # File.open and File.new take a path only on File; on IO they take a file descriptor.
    module FilePatch
      def open(name, *args, **kwargs, &block)
        result = super
        if FastCov::FileTracker.active && FastCov::FileTracker.read_mode?(args[0])
          FastCov::FileTracker.record(name)
        end
        result
      end

      def new(name, *args, **kwargs, &block)
        result = super
        if FastCov::FileTracker.active && FastCov::FileTracker.read_mode?(args[0])
          FastCov::FileTracker.record(name)
        end
        result
      end
    end

    module YamlPatch
      def load_file(path, ...)
        result = super
        FastCov::FileTracker.record(path) if FastCov::FileTracker.active
        result
      end

      def safe_load_file(path, ...)
        result = super
        FastCov::FileTracker.record(path) if FastCov::FileTracker.active
        result
      end

      def unsafe_load_file(path, ...)
        result = super
        FastCov::FileTracker.record(path) if FastCov::FileTracker.active
        result
      end
    end
  end
end
