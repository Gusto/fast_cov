# frozen_string_literal: true

require "benchmark"
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
      #   :merged  — after merging. Yields (file_count, elapsed)
      def on(event, &block)
        @hooks[event] = block
        self
      end

      # Iterate over merged results.
      # Without batch_size: yields (file_path, dependencies) per file.
      # With batch_size: yields a Hash of { file => dependencies } per batch.
      def each(batch_size = nil, &block)
        raise ArgumentError, "each requires a block" unless block
        return if @fragment_paths.empty?

        Dir.mktmpdir("fast_cov_aggregation") do |tmpdir|
          intermediates = create_intermediates(tmpdir)
          readers = intermediates.map { |f| Reader.new(f) }

          if batch_size
            merge_batched(readers, batch_size, &block)
          else
            merge_unbatched(readers, &block)
          end
        end
      end

      private

      def emit(event, *args)
        @hooks[event]&.call(*args)
      end

      def create_intermediates(intermediates_dir)
        batch_size = (@fragment_paths.size.to_f / @max_readers).ceil
        batches = @fragment_paths.each_slice(batch_size).to_a

        emit(:sort, @fragment_paths.size, batches.size)

        intermediates = nil
        elapsed = Benchmark.realtime do
          intermediates = batches.each_with_index.map do |batch, i|
            intermediate = File.join(intermediates_dir, "intermediate_#{i}.txt")
            lines = batch.flat_map { |f| Zlib::GzipReader.open(f) { |gz| gz.readlines } }
            lines.sort!
            File.write(intermediate, lines.join)
            intermediate
          end
        end

        emit(:sorted, elapsed)
        intermediates
      end

      def merge_unbatched(readers)
        unique_files = 0

        elapsed = Benchmark.realtime do
          loop do
            active = readers.reject(&:exhausted?)
            break if active.empty?

            min_path = active.map(&:file_path).min

            merged = Set.new
            active.each do |reader|
              if reader.file_path == min_path
                merged.merge(reader.dependencies)
                reader.advance
              end
            end

            yield min_path, merged.to_a.sort
            unique_files += 1
          end
        end

        readers.each(&:close)
        emit(:merged, unique_files, elapsed)
      end

      def merge_batched(readers, batch_size)
        unique_files = 0
        batch = {}

        elapsed = Benchmark.realtime do
          loop do
            active = readers.reject(&:exhausted?)
            break if active.empty?

            min_path = active.map(&:file_path).min

            merged = Set.new
            active.each do |reader|
              if reader.file_path == min_path
                merged.merge(reader.dependencies)
                reader.advance
              end
            end

            batch[min_path] = merged.to_a.sort
            unique_files += 1

            if batch.size >= batch_size
              yield batch
              batch = {}
            end
          end
        end

        yield batch unless batch.empty?

        readers.each(&:close)
        emit(:merged, unique_files, elapsed)
      end
    end
  end
end
