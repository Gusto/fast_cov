# frozen_string_literal: true

require "tmpdir"
require "zlib"

module FastCov
  class TestMap
    # Handles k-way merge of sorted fragment files.
    # Created by TestMap.aggregate, not instantiated directly.
    #
    # Usage:
    #   aggregator = FastCov::TestMap.aggregate(Dir["tmp/test_mapping.*.gz"])
    #   aggregator.on(:sorted) { |elapsed| puts "Sorted in #{elapsed.round(2)}s" }
    #   aggregator.on(:merged) { |files, elapsed| puts "Merged #{files} files in #{elapsed.round(2)}s" }
    #   aggregator.each(10_000) { |batch| database.bulk_write(batch) }
    class Aggregator
      def initialize(fragment_paths, max_readers)
        @fragment_paths = fragment_paths
        @max_readers = max_readers
        @hooks = {}
      end

      # Register a callback for an aggregation event.
      #
      # Events:
      #   :sort    — before sorting. Yields (fragment_count, batch_count)
      #   :sorted  — after sorting. Yields (elapsed)
      #   :merge   — during merge. Yields (processed_lines, total_lines)
      #   :merged  — after merging. Yields (file_count, elapsed)
      def on(event, &block)
        @hooks[event] = block
        self
      end

      # Iterate over merged results.
      # Yields a Hash of { file => dependencies } per batch.
      # Default batch_size is 1.
      def each(batch_size = 1, &block)
        raise ArgumentError, "each requires a block" unless block
        return if @fragment_paths.empty?

        Dir.mktmpdir("fastcov") do |tmpdir|
          intermediates, total_lines = create_intermediates(tmpdir)
          readers = intermediates.map { |f| Reader.new(f) }
          kway_merge(readers, batch_size, total_lines, &block)
        ensure
          readers&.each(&:close)
        end
      end

      private

      def emit(event, *args)
        @hooks[event]&.call(*args)
      end

      def measure
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        [result, elapsed]
      end

      def create_intermediates(intermediates_dir)
        batch_size = (@fragment_paths.size.to_f / @max_readers).ceil
        batches = @fragment_paths.each_slice(batch_size).to_a

        emit(:sort, @fragment_paths.size, batches.size)

        total_lines = 0
        intermediates, elapsed = measure do
          batches.each_with_index.map do |batch, i|
            intermediate = File.join(intermediates_dir, "intermediate_#{i}.txt")
            lines = batch.flat_map { |f| Zlib::GzipReader.open(f) { |gz| gz.readlines } }
            total_lines += lines.size
            lines.sort!
            File.write(intermediate, lines.join)
            intermediate
          end
        end

        emit(:sorted, elapsed)
        [intermediates, total_lines]
      end

      def kway_merge(readers, batch_size, total_lines, &block)
        unique_files = 0
        processed_lines = 0
        batch = {}

        _, elapsed = measure do
          loop do
            active = readers.reject(&:exhausted?)
            break if active.empty?

            min_path = active.map(&:file_path).min

            merged = Set.new
            active.each do |reader|
              if reader.file_path == min_path
                processed_lines += 1
                merged.merge(reader.dependencies)
                reader.advance
              end
            end

            emit(:merge, processed_lines, total_lines)
            unique_files += 1

            batch[min_path] = merged.to_a.sort
            if batch.size >= batch_size
              block.call(batch)
              batch = {}
            end
          end
        end

        block.call(batch) unless batch.empty?

        emit(:merged, unique_files, elapsed)
      end
    end
  end
end
