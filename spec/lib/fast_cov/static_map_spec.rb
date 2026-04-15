# frozen_string_literal: true

require "fileutils"
require "pathname"
require "set"
require "tmpdir"

# Load cycle fixtures eagerly so const_source_location resolves to real files
module CycleFixture; end
require_relative "../../fixtures/cycle/alpha"
require_relative "../../fixtures/cycle/beta"
require_relative "../../fixtures/cycle/entry"

RSpec.describe FastCov::StaticMap do
  describe "#build" do
    it "returns transitive dependencies of the input files" do
      with_static_map_fixture do |root|
        static_map = described_class.new(root: root)
        deps = static_map.build("spec/*_spec.rb")

        expect(deps).to eq([
          "app/static_map_autoload_fixture/dependency.rb",
          "app/static_map_autoload_fixture/entry_point.rb",
          "app/static_map_autoload_fixture/leaf.rb"
        ])
      end
    end

    it "populates the direct graph with relative paths" do
      with_static_map_fixture do |root|
        static_map = described_class.new(root: root)
        static_map.build("spec/*_spec.rb")

        expect(static_map.direct_graph).to eq(
          "spec/static_map_autoload_fixture_spec.rb" => ["app/static_map_autoload_fixture/entry_point.rb"],
          "app/static_map_autoload_fixture/entry_point.rb" => ["app/static_map_autoload_fixture/dependency.rb"],
          "app/static_map_autoload_fixture/dependency.rb" => ["app/static_map_autoload_fixture/leaf.rb"],
          "app/static_map_autoload_fixture/leaf.rb" => []
        )
      end
    end

    it "does not reuse caches across instances" do
      with_static_map_fixture do |root|
        static_map_a = described_class.new(root: root)
        static_map_a.build("spec/*_spec.rb")

        static_map_b = described_class.new(root: root)
        static_map_b.build("spec/*_spec.rb")

        expect(static_map_a.direct_graph).to eq(static_map_b.direct_graph)
        expect(static_map_a.direct_graph).not_to equal(static_map_b.direct_graph)
      end
    end

    it "expands relative file globs against root" do
      with_static_map_fixture do |root|
        expected = [
          "app/static_map_autoload_fixture/dependency.rb",
          "app/static_map_autoload_fixture/entry_point.rb",
          "app/static_map_autoload_fixture/leaf.rb"
        ]

        Dir.mktmpdir("fast_cov_static_map_cwd") do |cwd|
          Dir.chdir(cwd) do
            static_map = described_class.new(root: root)

            expect(static_map.build("spec/*_spec.rb")).to eq(expected)
          end
        end
      end
    end

    it "accepts root as a Pathname" do
      with_static_map_fixture do |root|
        static_map = described_class.new(root: Pathname.new(root))
        deps = static_map.build("spec/*_spec.rb")

        expect(deps).to include("app/static_map_autoload_fixture/entry_point.rb")
      end
    end

    it "handles missing constants gracefully" do
      Dir.mktmpdir("fast_cov_static_map") do |root|
        spec_file = File.join(root, "spec/missing_spec.rb")

        write_file(spec_file, <<~RUBY)
          MissingStaticMapFixture::Dependency
        RUBY

        static_map = described_class.new(root: root)
        deps = static_map.build(spec_file)

        expect(deps).to eq([])
      end
    end

    it "accepts both relative and absolute paths for lookup" do
      with_static_map_fixture do |root|
        static_map = described_class.new(root: root)
        absolute_path = File.join(root, "spec/static_map_autoload_fixture_spec.rb")

        expect(static_map.build("spec/static_map_autoload_fixture_spec.rb")).to eq(
          static_map.build(absolute_path)
        )
      end
    end

    it "traverses discovered dependencies only once even with cycles" do
      root = fixtures_path("cycle")

      static_map = described_class.new(root: root)
      static_map.build("entry.rb")

      expect(static_map.direct_graph).to eq(
        "entry.rb" => ["alpha.rb"],
        "alpha.rb" => ["beta.rb"],
        "beta.rb" => ["alpha.rb"]
      )
    end

    it "respects ignored paths while traversing the graph" do
      with_static_map_fixture do |root|
        leaf_file = File.join(root, "app/static_map_autoload_fixture/leaf.rb")

        static_map = described_class.new(root: root, ignored_paths: leaf_file)
        static_map.build("spec/*_spec.rb")

        expect(static_map.direct_graph).to eq(
          "spec/static_map_autoload_fixture_spec.rb" => ["app/static_map_autoload_fixture/entry_point.rb"],
          "app/static_map_autoload_fixture/entry_point.rb" => ["app/static_map_autoload_fixture/dependency.rb"],
          "app/static_map_autoload_fixture/dependency.rb" => []
        )
      end
    end

    it "skips files with syntax errors without crashing" do
      Dir.mktmpdir("fast_cov_static_map") do |root|
        good_file = File.join(root, "spec/good_spec.rb")
        bad_file = File.join(root, "spec/bad_spec.rb")

        write_file(good_file, "String\n")
        write_file(bad_file, "def foo(\n")

        static_map = described_class.new(root: root)
        deps = static_map.build(good_file, bad_file)

        expect(static_map.direct_graph).to have_key("spec/good_spec.rb")
        expect(static_map.direct_graph).to have_key("spec/bad_spec.rb")
        expect(static_map.direct_graph["spec/bad_spec.rb"]).to eq([])
      end
    end

    it "produces the same graph when called in batches as a single call" do
      with_static_map_fixture do |root|
        spec_file = File.join(root, "spec/static_map_autoload_fixture_spec.rb")

        single_call = described_class.new(root: root)
        single_call.build(spec_file)

        batched = described_class.new(root: root)
        # Build the spec file alone first, then build again — dependencies
        # discovered in the first call should not be re-processed.
        batched.build(spec_file)

        expect(batched.direct_graph).to eq(single_call.direct_graph)
      end
    end

    it "skips re-parsing files already in the graph from a prior build call" do
      with_static_map_fixture do |root|
        spec_file = File.join(root, "spec/static_map_autoload_fixture_spec.rb")
        entry_point_file = File.join(root, "app/static_map_autoload_fixture/entry_point.rb")

        static_map = described_class.new(root: root)

        # First build processes the full dependency chain
        static_map.build(spec_file)

        parse_calls = []
        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract).and_wrap_original do |original, path|
          parse_calls << path
          original.call(path)
        end

        # Second build with the same file — everything is already in the graph,
        # so no files should be parsed.
        static_map.build(spec_file)

        expect(parse_calls).to be_empty
      end
    end

    it "only parses new files when building incrementally" do
      with_static_map_fixture do |root|
        spec_file = File.join(root, "spec/static_map_autoload_fixture_spec.rb")

        # Add a second spec that shares the same dependency chain
        second_spec = File.join(root, "spec/second_spec.rb")
        write_file(second_spec, <<~RUBY)
          StaticMapAutoloadFixture::Leaf
        RUBY

        static_map = described_class.new(root: root)
        static_map.build(spec_file)

        parse_calls = []
        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract).and_wrap_original do |original, path|
          parse_calls << path
          original.call(path)
        end

        # Second build with a new spec file — only the new spec should be parsed,
        # not the shared dependencies already in the graph.
        static_map.build(second_spec)

        expect(parse_calls).to eq([second_spec])
      end
    end
  end

  describe "#direct_dependencies" do
    it "returns direct dependencies for a file" do
      with_static_map_fixture do |root|
        static_map = described_class.new(root: root)
        static_map.build("spec/*_spec.rb")

        expect(static_map.direct_dependencies("spec/static_map_autoload_fixture_spec.rb")).to eq(
          ["app/static_map_autoload_fixture/entry_point.rb"]
        )
      end
    end

    it "returns an empty array for unknown files" do
      static_map = described_class.new(root: Dir.pwd)

      expect(static_map.direct_dependencies("/nonexistent/file.rb")).to eq([])
    end
  end

  describe "#dependencies" do
    it "computes the transitive closure for a file" do
      with_static_map_fixture do |root|
        static_map = described_class.new(root: root)
        static_map.build("spec/*_spec.rb")

        expect(static_map.dependencies("spec/static_map_autoload_fixture_spec.rb")).to eq([
          "app/static_map_autoload_fixture/dependency.rb",
          "app/static_map_autoload_fixture/entry_point.rb",
          "app/static_map_autoload_fixture/leaf.rb"
        ])
      end
    end

    it "excludes ignored paths from the transitive closure" do
      with_static_map_fixture do |root|
        leaf_file = File.join(root, "app/static_map_autoload_fixture/leaf.rb")

        static_map = described_class.new(root: root, ignored_paths: leaf_file)
        static_map.build("spec/*_spec.rb")

        expect(static_map.dependencies("spec/static_map_autoload_fixture_spec.rb")).to eq([
          "app/static_map_autoload_fixture/dependency.rb",
          "app/static_map_autoload_fixture/entry_point.rb"
        ])
      end
    end

    it "handles cycles in transitive dependencies" do
      root = fixtures_path("cycle")

      static_map = described_class.new(root: root)
      static_map.build("entry.rb")

      expect(static_map.dependencies("entry.rb")).to eq(["alpha.rb", "beta.rb"])
    end

    it "handles deep dependency chains without recursive stack growth" do
      Dir.mktmpdir("fast_cov_static_map") do |root|
        spec_file = File.join(root, "spec/deep_spec.rb")
        depth = 12_000
        dependency_files = Array.new(depth) { |index| File.join(root, "app/deep/file_#{index}.rb") }
        synthetic_files = dependency_files.to_set << spec_file

        write_file(spec_file, "# synthetic\n")

        allow(File).to receive(:file?).and_wrap_original do |original, path|
          synthetic_files.include?(path) || original.call(path)
        end

        extracts = {}
        extracts[spec_file] = [["DeepConst0"]].freeze

        dependency_files.each_with_index do |dependency_file, index|
          extracts[dependency_file] =
            if index == depth - 1
              FastCov::StaticMap::EMPTY_ARRAY
            else
              [["DeepConst#{index + 1}"]].freeze
            end
        end

        dependency_files.each_with_index do |_, index|
          stub_const("DeepConst#{index}", Module.new)
        end

        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract) do |path|
          extracts.fetch(path)
        end
        allow(Object).to receive(:const_source_location).and_call_original
        dependency_files.each_with_index do |dependency_file, index|
          allow(Object).to receive(:const_source_location).with("DeepConst#{index}").and_return([dependency_file, 1])
        end

        static_map = described_class.new(root: root)
        static_map.build(spec_file)

        expected = dependency_files.map { |f| f.delete_prefix("#{root}/") }.sort
        expect(static_map.dependencies("spec/deep_spec.rb")).to eq(expected)
      end
    end

    it "returns an empty array for unknown files" do
      static_map = described_class.new(root: Dir.pwd)

      expect(static_map.dependencies("/nonexistent/file.rb")).to eq([])
    end
  end

  def with_static_map_fixture
    Dir.mktmpdir("fast_cov_static_map") do |root|
      stub_const("StaticMapAutoloadFixture", Module.new)

      write_file(File.join(root, "spec/static_map_autoload_fixture_spec.rb"), <<~RUBY)
        RSpec.describe StaticMapAutoloadFixture::EntryPoint do
          it "references the autoloaded entry point" do
            described_class::NAME
          end
        end
      RUBY

      write_file(File.join(root, "app/static_map_autoload_fixture/entry_point.rb"), <<~RUBY)
        module StaticMapAutoloadFixture
          class EntryPoint
            NAME = Dependency::NAME
          end
        end
      RUBY

      write_file(File.join(root, "app/static_map_autoload_fixture/dependency.rb"), <<~RUBY)
        module StaticMapAutoloadFixture
          class Dependency
            NAME = Leaf::NAME
          end
        end
      RUBY

      write_file(File.join(root, "app/static_map_autoload_fixture/leaf.rb"), <<~RUBY)
        module StaticMapAutoloadFixture
          class Leaf
            NAME = "leaf"
          end
        end
      RUBY

      StaticMapAutoloadFixture.autoload(:EntryPoint, File.join(root, "app/static_map_autoload_fixture/entry_point.rb"))
      StaticMapAutoloadFixture.autoload(:Dependency, File.join(root, "app/static_map_autoload_fixture/dependency.rb"))
      StaticMapAutoloadFixture.autoload(:Leaf, File.join(root, "app/static_map_autoload_fixture/leaf.rb"))

      # Eager-load to simulate a booted application — const_source_location
      # only returns the real file path after the constant is loaded.
      StaticMapAutoloadFixture::Leaf
      StaticMapAutoloadFixture::Dependency
      StaticMapAutoloadFixture::EntryPoint

      yield(root)
    end
  end

  def write_file(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end
end
