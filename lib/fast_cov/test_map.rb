# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "zlib"

module FastCov
  # In-memory test mapping that records which files each test depends on.
  # Can be dumped to a gzipped TSV fragment file for later aggregation.
  #
  # Usage:
  #   # Accumulate mappings (e.g., in an RSpec formatter)
  #   test_map = FastCov::TestMap.new
  #   test_map.add("spec/models/user_spec.rb" => coverage_result)
  #   test_map.dump("tmp/test_mapping.node_0.gz")
  #
  #   # Query mappings
  #   test_map.dependencies("app/models/user.rb")
  #   # => ["spec/models/user_spec.rb"]
  #
  #   # Aggregate fragments from multiple nodes
  #   FastCov::TestMap.aggregate("tmp/test_mapping.*.gz") do |file, dependencies|
  #     database.insert(file, dependencies)
  #   end
  class TestMap
    autoload :Reader, File.expand_path("test_map/reader", __dir__)

    DEFAULT_MAX_READERS = [100, Process.getrlimit(Process::RLIMIT_NOFILE).first / 2].min

    def initialize
      @mapping = {}
    end

    # Record test -> dependency mappings.
    # Accepts a Hash of { test_path => dependencies }.
    def add(mappings)
      mappings.each do |test_path, deps|
        deps.each do |dep|
          next if dep == test_path

          (@mapping[dep] ||= Set.new) << test_path
        end
      end
    end

    # Returns the test paths that depend on the given file.
    def dependencies(file)
      (@mapping[file] || Set.new).to_a
    end

    # Write the accumulated mappings as a gzipped TSV fragment.
    # Format: source_file\tdep1,dep2,...
    def dump(path)
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

    # Merge multiple fragment files via k-way merge.
    # Accepts file paths or glob patterns.
    # Yields (source_file, dependencies) for each unique file.
    # Returns the number of unique files yielded.
    def self.aggregate(*patterns, readers: DEFAULT_MAX_READERS, &block)
      raise ArgumentError, "aggregate requires a block" unless block

      fragment_paths = patterns.flatten.flat_map { |p| p.include?("*") ? Dir.glob(p).sort : p }
      return 0 if fragment_paths.empty?

      if fragment_paths.size <= readers
        kway_merge(fragment_paths.map { |f| Reader.new(f) }, &block)
      else
        Dir.mktmpdir("fast_cov_aggregation") do |tmpdir|
          intermediates = create_intermediates(fragment_paths, readers, tmpdir)
          kway_merge(intermediates.map { |f| Reader.new(f) }, &block)
        end
      end
    end

    class << self
      private

      def create_intermediates(fragment_paths, max_readers, intermediates_dir)
        batch_size = (fragment_paths.size.to_f / max_readers).ceil
        batches = fragment_paths.each_slice(batch_size).to_a

        batches.each_with_index.map do |batch, i|
          intermediate = File.join(intermediates_dir, "intermediate_#{i}.txt")
          statuses = Open3.pipeline(
            ["gunzip", "--stdout", *batch],
            ["sort", "--field-separator", "\t", "--key", "1,1"],
            out: intermediate
          )
          unless statuses.all?(&:success?)
            raise "Failed to create intermediate file: #{intermediate}"
          end
          intermediate
        end
      end

      def kway_merge(readers, &block)
        unique_files = 0

        loop do
          active = readers.reject(&:exhausted?)
          break if active.empty?

          min_path = active.map(&:file_path).min

          merged = []
          active.each do |reader|
            if reader.file_path == min_path
              merged.concat(reader.dependencies)
              reader.advance
            end
          end

          block.call(min_path, merged.uniq.sort)
          unique_files += 1
        end

        readers.each(&:close)
        unique_files
      end
    end
  end
end
