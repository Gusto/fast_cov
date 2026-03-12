# frozen_string_literal: true

require "fileutils"
require "pathname"
require "set"
require "tmpdir"

RSpec.describe FastCov::StaticMap do
  describe ".build" do
    it "builds through an instance" do
      instance = described_class.new(files: [], root: Dir.pwd, ignored_paths: [])

      allow(described_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:build).and_return({})

      expect(described_class.build(files: [], root: Dir.pwd, ignored_paths: [])).to eq({})
      expect(described_class).to have_received(:new).with(files: [], root: Dir.pwd, ignored_paths: [])
      expect(instance).to have_received(:build)
    end

    it "builds a direct dependency graph for each reachable file" do
      with_static_map_fixture do |root, file|
        entry_point_file = File.join(root, "app/static_map_autoload_fixture/entry_point.rb")
        dependency_file = File.join(root, "app/static_map_autoload_fixture/dependency.rb")
        leaf_file = File.join(root, "app/static_map_autoload_fixture/leaf.rb")

        graph = described_class.build(
          files: file,
          root: root
        )

        expect(graph).to eq(
          file => [entry_point_file],
          entry_point_file => [dependency_file],
          dependency_file => [leaf_file]
        )
      end
    end

    it "does not reuse parsed references across build instances" do
      with_static_map_fixture do |root, file|
        described_class.build(files: file, root: root)

        allow(FastCov::StaticMap::ReferenceExtractor).to receive(:extract).and_call_original

        described_class.build(files: file, root: root)

        expect(FastCov::StaticMap::ReferenceExtractor).to have_received(:extract).at_least(:once)
      end
    end

    it "expands relative file globs against root" do
      with_static_map_fixture do |root, file|
        entry_point_file = File.join(root, "app/static_map_autoload_fixture/entry_point.rb")

        Dir.mktmpdir("fast_cov_static_map_cwd") do |cwd|
          Dir.chdir(cwd) do
            graph = described_class.build(
              files: "spec/*_spec.rb",
              root: root
            )

            expect(graph).to include(file => [entry_point_file])
          end
        end
      end
    end

    it "accepts root as a Pathname" do
      with_static_map_fixture do |root, file|
        entry_point_file = File.join(root, "app/static_map_autoload_fixture/entry_point.rb")

        graph = described_class.build(
          files: "spec/*_spec.rb",
          root: Pathname.new(root)
        )

        expect(graph).to include(file => [entry_point_file])
      end
    end

    it "caches missing constants for the process" do
      Dir.mktmpdir("fast_cov_static_map") do |root|
        entrypoint_a = File.join(root, "spec/one_spec.rb")
        entrypoint_b = File.join(root, "spec/two_spec.rb")

        write_file(entrypoint_a, <<~RUBY)
          MissingStaticMapFixture::Dependency
        RUBY
        write_file(entrypoint_b, <<~RUBY)
          MissingStaticMapFixture::Dependency
        RUBY

        allow(Object).to receive(:const_get).and_call_original

        mapping = described_class.build(
          files: File.join(root, "spec/*_spec.rb"),
          root: root
        )

        expect(mapping).to eq({})
        expect(Object).to have_received(:const_get).with("MissingStaticMapFixture::Dependency").once
      end
    end

    it "treats unexpected autoload errors as misses" do
      Dir.mktmpdir("fast_cov_static_map") do |root|
        spec_file = File.join(root, "spec/autoload_error_spec.rb")
        write_file(spec_file, <<~RUBY)
          AutoloadErrorFixture::Dependency
        RUBY

        allow(Object).to receive(:const_get).and_wrap_original do |original, const_name, *rest|
          if const_name == "AutoloadErrorFixture::Dependency"
            raise Errno::ENOENT, "autoload side effect"
          end

          original.call(const_name, *rest)
        end

        expect(described_class.build(files: spec_file, root: root)).to eq({})
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

        allow_any_instance_of(described_class).to receive(:constant_loaded?).and_return(true)
        allow(Object).to receive(:const_source_location) do |const_name|
          case const_name
          when "CycleConstA"
            [file_a, 1]
          when "CycleConstB"
            [file_b, 1]
          end
        end

        graph = described_class.build(files: spec_file, root: root)

        expect(graph).to eq(
          spec_file => [file_a],
          file_a => [file_b],
          file_b => [file_a]
        )
      end
    end

    it "respects ignored paths while traversing the graph" do
      with_static_map_fixture do |root, file|
        entry_point_file = File.join(root, "app/static_map_autoload_fixture/entry_point.rb")
        dependency_file = File.join(root, "app/static_map_autoload_fixture/dependency.rb")
        leaf_file = File.join(root, "app/static_map_autoload_fixture/leaf.rb")

        graph = described_class.build(
          files: file,
          root: root,
          ignored_paths: leaf_file
        )

        expect(graph).to eq(
          file => [entry_point_file],
          entry_point_file => [dependency_file]
        )
      end
    end
  end

  describe ".build_transitive" do
    it "builds through an instance" do
      instance = described_class.new(files: [], root: Dir.pwd, ignored_paths: [])

      allow(described_class).to receive(:new).and_return(instance)
      allow(instance).to receive(:build_transitive).and_return({})

      expect(described_class.build_transitive(files: [], root: Dir.pwd, ignored_paths: [])).to eq({})
      expect(described_class).to have_received(:new).with(files: [], root: Dir.pwd, ignored_paths: [])
      expect(instance).to have_received(:build_transitive)
    end

    it "builds a transitive dependency map for files" do
      with_static_map_fixture do |root, file|
        mapping = described_class.build_transitive(
          files: file,
          root: root
        )

        expect(mapping).to eq(
          file => [
            File.join(root, "app/static_map_autoload_fixture/dependency.rb"),
            File.join(root, "app/static_map_autoload_fixture/entry_point.rb"),
            File.join(root, "app/static_map_autoload_fixture/leaf.rb")
          ]
        )
      end
    end

    it "excludes ignored paths from the traversal" do
      with_static_map_fixture do |root, file|
        mapping = described_class.build_transitive(
          files: file,
          root: root,
          ignored_paths: File.join(root, "app/static_map_autoload_fixture/leaf.rb")
        )

        expect(mapping).to eq(
          file => [
            File.join(root, "app/static_map_autoload_fixture/dependency.rb"),
            File.join(root, "app/static_map_autoload_fixture/entry_point.rb")
          ]
        )
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
        allow_any_instance_of(described_class).to receive(:constant_loaded?).and_return(true)
        allow(Object).to receive(:const_source_location) do |const_name|
          locations[const_name]
        end

        mapping = described_class.build_transitive(files: spec_file, root: root)

        expect(mapping.fetch(spec_file)).to eq(dependency_files.sort)
      end
    end

    it "preserves cycle handling for transitive dependencies" do
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

        allow_any_instance_of(described_class).to receive(:constant_loaded?).and_return(true)
        allow(Object).to receive(:const_source_location) do |const_name|
          case const_name
          when "CycleConstA"
            [file_a, 1]
          when "CycleConstB"
            [file_b, 1]
          end
        end

        mapping = described_class.build_transitive(files: spec_file, root: root)

        expect(mapping.fetch(spec_file)).to eq([file_a, file_b])
      end
    end
  end

  def with_static_map_fixture
    Dir.mktmpdir("fast_cov_static_map") do |root|
      stub_const("StaticMapAutoloadFixture", Module.new)

      file = File.join(root, "spec/static_map_autoload_fixture_spec.rb")
      entry_point_file = File.join(root, "app/static_map_autoload_fixture/entry_point.rb")
      dependency_file = File.join(root, "app/static_map_autoload_fixture/dependency.rb")
      leaf_file = File.join(root, "app/static_map_autoload_fixture/leaf.rb")

      write_file(file, <<~RUBY)
        RSpec.describe StaticMapAutoloadFixture::EntryPoint do
          it "references the autoloaded entry point" do
            described_class::NAME
          end
        end
      RUBY

      write_file(entry_point_file, <<~RUBY)
        module StaticMapAutoloadFixture
          class EntryPoint
            NAME = Dependency::NAME
          end
        end
      RUBY

      write_file(dependency_file, <<~RUBY)
        module StaticMapAutoloadFixture
          class Dependency
            NAME = Leaf::NAME
          end
        end
      RUBY

      write_file(leaf_file, <<~RUBY)
        module StaticMapAutoloadFixture
          class Leaf
            NAME = "leaf"
          end
        end
      RUBY

      StaticMapAutoloadFixture.autoload(:EntryPoint, entry_point_file)
      StaticMapAutoloadFixture.autoload(:Dependency, dependency_file)
      StaticMapAutoloadFixture.autoload(:Leaf, leaf_file)

      yield(root, file)
    end
  end

  def write_file(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end
end
