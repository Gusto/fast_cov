# frozen_string_literal: true

require "zlib"

module FastCov
  class TestMap
    # Reads a single sorted fragment file (gzipped or plain text).
    # Merges consecutive entries with the same file path, which occur when
    # multiple fragments are concatenated and sorted into an intermediate.
    class Reader
      attr_reader :file_path, :dependencies

      def initialize(path)
        @io = Zlib::GzipReader.open(path) rescue File.open(path)
        @exhausted = false
        @next_file_path = nil
        @next_dependencies = nil
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
          @dependencies = []
          return
        end

        @file_path = @next_file_path
        @dependencies = @next_dependencies
        read_line

        # Merge consecutive lines with the same file path
        while @next_file_path == @file_path
          @dependencies.concat(@next_dependencies)
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
          @next_dependencies = nil
          return
        end

        parts = line.chomp.split("\t")
        @next_file_path = parts[0]
        @next_dependencies = parts[1..] || []
      end
    end
  end
end
