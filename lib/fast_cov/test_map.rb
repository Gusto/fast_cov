# frozen_string_literal: true

require "fileutils"
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
  #   aggregator = FastCov::TestMap.aggregate(Dir["tmp/test_mapping.*.gz"])
  #   aggregator.on(:sorted) { |elapsed| puts "Sorted in #{elapsed.round(2)}s" }
  #   aggregator.on(:merged) { |files, elapsed| puts "Merged #{files} files in #{elapsed.round(2)}s" }
  #   aggregator.each(10_000) { |batch| database.bulk_write(batch) }
  class TestMap
    autoload :Aggregator, File.expand_path("test_map/aggregator", __dir__)
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
    def dump(path)
      FileUtils.mkdir_p(File.dirname(path))

      lines = @mapping.map { |file, deps| "#{file}\t#{deps.to_a.join("\t")}\n" }
      Zlib::GzipWriter.open(path) { |gz| gz.write(lines.join) }
    end

    # Number of unique source files mapped.
    def size
      @mapping.size
    end

    # Create an Aggregator for merging fragment files.
    # Accepts file paths or glob patterns.
    def self.aggregate(*patterns, readers: DEFAULT_MAX_READERS)
      fragment_paths = patterns.flatten.flat_map { |p| p.include?("*") ? Dir.glob(p).sort : p }
      Aggregator.new(fragment_paths, readers)
    end
  end
end
