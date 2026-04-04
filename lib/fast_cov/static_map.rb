# frozen_string_literal: true

module FastCov
  class StaticMap
    EMPTY_ARRAY = [].freeze

    autoload :ReferenceExtractor, "fast_cov/static_map/reference_extractor"

    class << self
      def build(files:, root: Dir.pwd, ignored_paths: [])
        new(root: root, ignored_paths: ignored_paths).build(files: files)
      end
    end

    def initialize(root:, ignored_paths: [])
      @root = share_path(root)
      @ignored_paths = normalize_ignored_paths(ignored_paths)
      @resolved_file_by_const = {}
      @direct_dependencies_by_file = {}
      @closure_by_file = {}
      @graph = {}
    end

    def build(files:)
      queue = expand_files(files).select { |file| processable_file?(file) }
      processed = {}
      index = 0

      while index < queue.length
        file = queue[index]
        index += 1
        next if processed[file]

        processed[file] = true
        dependencies = direct_dependencies_for_file(file)
        @graph[file] = dependencies

        dependencies.each do |dependency|
          next if processed[dependency]
          next unless processable_file?(dependency)

          queue << dependency
        end
      end

      self
    end

    def direct_graph
      @graph
    end

    def dependencies(file)
      @graph.fetch(share_path(file), EMPTY_ARRAY)
    end

    def transitive_dependencies(file)
      file = share_path(file)
      resolve_transitive_dependencies(file)
    end

    private

    attr_reader :closure_by_file, :direct_dependencies_by_file, :ignored_paths,
                :resolved_file_by_const, :root

    def resolve_transitive_dependencies(file)
      cached = closure_by_file[file]
      return cached if cached

      visiting = {}
      local_deps = {}
      stack = [[file, :enter]]

      until stack.empty?
        current_file, state = stack.pop

        if state == :exit
          dependencies = {}

          @graph.fetch(current_file, EMPTY_ARRAY).each do |dependency_file|
            dependencies[dependency_file] = true

            closure_by_file.fetch(dependency_file, EMPTY_ARRAY).each do |transitive_dependency|
              dependencies[transitive_dependency] = true
            end
          end

          dependencies.delete(current_file)
          closure_by_file[current_file] = dependencies.empty? ? EMPTY_ARRAY : dependencies.keys.sort.freeze
          visiting.delete(current_file)
          next
        end

        next if closure_by_file.key?(current_file)
        next if visiting[current_file]

        visiting[current_file] = true
        stack << [current_file, :exit]

        @graph.fetch(current_file, EMPTY_ARRAY).reverse_each do |dependency_file|
          next if closure_by_file.key?(dependency_file)
          next if visiting[dependency_file]

          stack << [dependency_file, :enter]
        end
      end

      closure_by_file.fetch(file, EMPTY_ARRAY)
    end

    def resolve_reference_group(candidates)
      candidates.each do |const_name|
        resolved_file = resolve_constant_file(const_name)
        return resolved_file if resolved_file
      end

      nil
    end

    def resolve_constant_file(const_name)
      shared_const_name = share_string(const_name)

      cached = resolved_file_by_const[shared_const_name]
      return cached if cached
      return nil unless constant_defined?(shared_const_name)

      source_location = Object.const_source_location(shared_const_name)
      file = source_location&.first
      return nil unless file && File.file?(file)

      resolved_file_by_const[shared_const_name] = share_path(file)
    rescue StandardError
      nil
    end

    def constant_defined?(const_name)
      current = Object

      const_name.split("::").each do |segment|
        return false unless current.const_defined?(segment, false)

        current = current.const_get(segment, false)
      end

      true
    rescue StandardError
      false
    end

    def reference_groups_for(file)
      ReferenceExtractor.extract(file)
    end

    def direct_dependencies_for_file(file)
      return direct_dependencies_by_file[file] if direct_dependencies_by_file.key?(file)

      dependencies = {}

      reference_groups_for(file).each do |candidates|
        resolved_file = resolve_reference_group(candidates)
        next unless resolved_file
        next unless include_path?(resolved_file)

        dependencies[resolved_file] = true
      end

      dependencies.delete(file)
      direct_dependencies_by_file[file] = dependencies.empty? ? EMPTY_ARRAY : dependencies.keys.sort.freeze
    end

    def include_path?(path)
      return false unless FastCov::Utils.path_within?(path, root)

      ignored_paths.none? { |ignored_path| FastCov::Utils.path_within?(path, ignored_path) }
    end

    def processable_file?(file)
      File.file?(file) && include_path?(file)
    end

    def expand_files(patterns)
      Array(patterns)
        .flat_map do |pattern|
          expanded_pattern = if pattern.to_s.start_with?("/")
            pattern.to_s
          else
            File.expand_path(pattern.to_s, root)
          end

          Dir.glob(expanded_pattern)
        end
        .map { |path| share_path(path) }
        .uniq
        .sort
    end

    def normalize_ignored_paths(ignored_paths)
      Array(ignored_paths)
        .compact
        .map { |path| share_path(File.expand_path(path, root)) }
        .uniq
        .sort
        .freeze
    end

    def share_path(path)
      share_string(File.expand_path(path.to_s))
    end

    def share_string(string)
      -string.to_s
    end
  end
end
