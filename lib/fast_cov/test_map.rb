# frozen_string_literal: true

require "fileutils"
require "shellwords"

module FastCov
  # Merges multiple test mapping fragments via k-way merge.
  #
  # Each fragment is a gzipped TSV file mapping source files to spec directories,
  # produced by Fragment during test runs or static analysis.
  #
  # Usage:
  #   map = FastCov::TestMap.new
  #   map.build(fragment_paths) do |source_file, spec_paths|
  #     database.insert(source_file, spec_paths)
  #   end
  class TestMap
    autoload :Fragment, File.expand_path("test_map/fragment", __dir__)
    autoload :Reader, File.expand_path("test_map/reader", __dir__)

    DEFAULT_MAX_READERS = 50

    def initialize(max_readers: DEFAULT_MAX_READERS, intermediates_dir: nil)
      @max_readers = max_readers
      @intermediates_dir = intermediates_dir || "tmp/fast_cov_intermediates"
    end

    # Merge fragment files and yield each unique (source_file, spec_paths) pair.
    # Returns the number of unique files yielded.
    def build(fragment_paths)
      raise ArgumentError, "build requires a block" unless block_given?
      return 0 if fragment_paths.empty?

      if fragment_paths.size <= @max_readers
        kway_merge(fragment_paths.map { |f| Reader.new(f) }) { |file, paths| yield file, paths }
      else
        intermediates = create_intermediates(fragment_paths)
        begin
          kway_merge(intermediates.map { |f| Reader.new(f) }) { |file, paths| yield file, paths }
        ensure
          intermediates.each { |f| File.delete(f) if File.exist?(f) }
          Dir.rmdir(@intermediates_dir) if Dir.exist?(@intermediates_dir) && Dir.empty?(@intermediates_dir)
        end
      end
    end

    private

    def create_intermediates(fragment_paths)
      FileUtils.mkdir_p(@intermediates_dir)

      batch_size = (fragment_paths.size.to_f / @max_readers).ceil
      batches = fragment_paths.each_slice(batch_size).to_a

      batches.each_with_index.map do |batch, i|
        intermediate = File.join(@intermediates_dir, "intermediate_#{i}.txt")
        escaped = batch.map { |f| Shellwords.escape(f) }.join(" ")
        system("gunzip -c #{escaped} | sort -t'\t' -k1,1 > #{Shellwords.escape(intermediate)}", exception: true)
        intermediate
      end
    end

    def kway_merge(readers)
      unique_files = 0

      loop do
        active = readers.reject(&:exhausted?)
        break if active.empty?

        min_path = active.map(&:file_path).min

        merged_spec_paths = []
        active.each do |reader|
          if reader.file_path == min_path
            merged_spec_paths.concat(reader.spec_paths)
            reader.advance
          end
        end

        yield min_path, merged_spec_paths.uniq.sort
        unique_files += 1
      end

      readers.each(&:close)
      unique_files
    end
  end
end
