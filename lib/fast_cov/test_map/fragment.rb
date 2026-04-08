# frozen_string_literal: true

require "zlib"

module FastCov
  class TestMap
    # Accumulates test mappings and writes a gzipped TSV file.
    #
    # Each call to `add` records which source files a spec depends on,
    # transposed so the output maps source files to spec directories.
    #
    # Output format: gzipped TSV, sorted by file path
    #   app/models/user.rb\tspec/models/,packs/core/spec/models/
    class Fragment
      def initialize
        @mapping = {}
      end

      # Record that spec_file depends on the given dependencies.
      # Transposes the relationship: each dependency maps to the spec file's directory.
      def add(spec_file, dependencies)
        spec_dir = "#{File.dirname(spec_file)}/"

        dependencies.each do |dep|
          next if dep == spec_file

          (@mapping[dep] ||= Set.new) << spec_dir
        end
      end

      # Write the accumulated mappings as gzipped TSV, sorted by file path.
      def write(path)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        Zlib::GzipWriter.open(path) do |gzip|
          @mapping.keys.sort.each do |file|
            gzip.puts("#{file}\t#{@mapping[file].to_a.sort.join(",")}")
          end
        end
      end

      # Number of unique source files mapped.
      def size
        @mapping.size
      end
    end
  end
end
