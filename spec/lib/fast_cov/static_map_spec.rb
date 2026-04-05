# frozen_string_literal: true

require "fileutils"
require "pathname"
require "set"
require "tmpdir"

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

    it "does not reuse parsed references across build instances" do
      with_static_map_fixture do |root|
        described_class.new(root: root).build("spec/*_spec.rb")

        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract).and_call_original

        described_class.new(root: root).build("spec/*_spec.rb")

        expect(FastCov::StaticMap::ReferenceExtractor).to have_received(:extract).at_least(:once)
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
      Dir.mktmpdir("fast_cov_static_map") do |root|
        spec_file = File.join(root, "spec/cycle_spec.rb")
        file_a = File.join(root, "app/cycle/a.rb")
        file_b = File.join(root, "app/cycle/b.rb")
        synthetic_files = [spec_file, file_a, file_b].to_set

        write_file(spec_file, "# synthetic\n")

        allow(File).to receive(:file?).and_wrap_original do |original, path|
          synthetic_files.include?(path) || original.call(path)
        end

        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract) do |path|
          case path
          when spec_file
            [["CycleConstA"]]
          when file_a
            [["CycleConstB"]]
          when file_b
            [["CycleConstA"]]
          else
            raise "unexpected file: #{path}"
          end
        end

        allow_any_instance_of(described_class).to receive(:constant_defined?).and_return(true)
        allow(Object).to receive(:const_source_location) do |const_name|
          case const_name
          when "CycleConstA"
            [file_a, 1]
          when "CycleConstB"
            [file_b, 1]
          end
        end

        static_map = described_class.new(root: root)
        static_map.build(spec_file)

        expect(static_map.direct_graph).to eq(
          "spec/cycle_spec.rb" => ["app/cycle/a.rb"],
          "app/cycle/a.rb" => ["app/cycle/b.rb"],
          "app/cycle/b.rb" => ["app/cycle/a.rb"]
        )
      end
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

        locations = dependency_files.each_with_index.to_h do |dependency_file, index|
          ["DeepConst#{index}", [dependency_file, 1]]
        end

        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract) do |path|
          extracts.fetch(path)
        end
        allow_any_instance_of(described_class).to receive(:constant_defined?).and_return(true)
        allow(Object).to receive(:const_source_location) do |const_name|
          locations[const_name]
        end

        static_map = described_class.new(root: root)
        static_map.build(spec_file)

        expected = dependency_files.map { |f| f.delete_prefix("#{root}/") }.sort
        expect(static_map.dependencies("spec/deep_spec.rb")).to eq(expected)
      end
    end

    it "handles cycles in transitive dependencies" do
      Dir.mktmpdir("fast_cov_static_map") do |root|
        spec_file = File.join(root, "spec/cycle_spec.rb")
        file_a = File.join(root, "app/cycle/a.rb")
        file_b = File.join(root, "app/cycle/b.rb")
        synthetic_files = [spec_file, file_a, file_b].to_set

        write_file(spec_file, "# synthetic\n")

        allow(File).to receive(:file?).and_wrap_original do |original, path|
          synthetic_files.include?(path) || original.call(path)
        end

        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract) do |path|
          case path
          when spec_file
            [["CycleConstA"]]
          when file_a
            [["CycleConstB"]]
          when file_b
            [["CycleConstA"]]
          else
            raise "unexpected file: #{path}"
          end
        end

        allow_any_instance_of(described_class).to receive(:constant_defined?).and_return(true)
        allow(Object).to receive(:const_source_location) do |const_name|
          case const_name
          when "CycleConstA"
            [file_a, 1]
          when "CycleConstB"
            [file_b, 1]
          end
        end

        static_map = described_class.new(root: root)
        static_map.build(spec_file)

        expect(static_map.dependencies("spec/cycle_spec.rb")).to eq(["app/cycle/a.rb", "app/cycle/b.rb"])
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
