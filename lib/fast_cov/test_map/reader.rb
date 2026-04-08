# frozen_string_literal: true

require "zlib"

module FastCov
  class TestMap
    # Reads a single sorted manifest file (gzipped or plain text).
    # Merges consecutive entries with the same file path, which occur when
    # multiple fragments are concatenated and sorted into an intermediate.
    class Reader
      attr_reader :file_path, :spec_paths

      def initialize(path)
        @io = path.to_s.end_with?(".gz") ? Zlib::GzipReader.open(path) : File.open(path)
        @exhausted = false
        @next_file_path = nil
        @next_spec_paths = nil
        read_line
        advance
      end

      def exhausted?
        @exhausted
      end

      def advance
        if @next_file_path.nil?
          @exhausted = true
          @file_path = nil
          @spec_paths = []
          return
        end

        @file_path = @next_file_path
        @spec_paths = @next_spec_paths
        read_line

        # Merge consecutive lines with the same file path
        while @next_file_path == @file_path
          @spec_paths.concat(@next_spec_paths)
          read_line
        end
      end

      def close
        @io.close
      end

      private

      def read_line
        line = @io.gets
        if line.nil?
          @next_file_path = nil
          @next_spec_paths = nil
          return
        end

        file_path, spec_paths_str = line.chomp.split("\t", 2)
        @next_file_path = file_path
        @next_spec_paths = spec_paths_str&.split(",") || []
      end
    end
  end
end
