# frozen_string_literal: true

module FastCov
  class StaticMap
    EMPTY_ARRAY = [].freeze

    autoload :ReferenceExtractor, File.expand_path("static_map/reference_extractor", __dir__)

    def initialize(root:, ignored_paths: [], concurrency: Etc.nprocessors)
      @root = share_path(root)
      @root_prefix = -"#{@root}/"
      @ignored_paths = normalize_ignored_paths(ignored_paths)
      @concurrency = concurrency
      @resolved_file_by_const = {}
      @closure_by_file = {}
      @graph = {}
    end

    def build(*patterns)
      input_files = expand_files(patterns.flatten).select { |file| processable_file?(file) }

      queue = input_files.dup
      processed = {}

      until queue.empty?
        to_process = queue.reject { |f| processed[f] || @graph.key?(relativize(f)) }
        break if to_process.empty?

        to_process.each { |f| processed[f] = true }
        queue.clear

        # Stage 1: Parse files (parallel)
        parsed = parse_files(to_process)

        # Stage 2: Resolve unique constants (sequential — GVL-bound)
        resolve_candidates(parsed)

        # Stage 3: Build graph edges, discover new files
        parsed.each do |file, groups|
          deps = resolve_dependencies(file, groups)
          relative_file = relativize(file)
          @graph[relative_file] = deps.empty? ? EMPTY_ARRAY : deps.map { |d| relativize(d) }.freeze

          deps.each do |dep|
            queue << dep unless processed[dep] || @graph.key?(relativize(dep))
          end
        end
      end

      input_files.flat_map { |file| dependencies(file) }.uniq
    end

    def direct_graph
      @graph
    end

    def direct_dependencies(file)
      @graph.fetch(relativize_input(file), EMPTY_ARRAY)
    end

    def dependencies(file)
      file = relativize_input(file)
      resolve_transitive_dependencies(file)
    end

    private

    attr_reader :closure_by_file, :ignored_paths, :resolved_file_by_const, :root

    def parse_files(files)
      if @concurrency > 1 && files.size > 1
        parse_files_parallel(files)
      else
        parse_files_sequential(files)
      end
    end

    def parse_files_sequential(files)
      parsed = {}
      files.each { |f| parsed[f] = ReferenceExtractor.extract(f) }
      parsed
    end

    def parse_files_parallel(files)
      parsed = {}
      mutex = Mutex.new
      slice_size = [files.size / @concurrency + 1, 1].max

      files.each_slice(slice_size).map do |slice|
        Thread.new(slice) do |thread_files|
          local = {}
          thread_files.each { |f| local[f] = ReferenceExtractor.extract(f) }
          mutex.synchronize { parsed.merge!(local) }
        end
      end.each(&:join)

      parsed
    end

    def resolve_candidates(parsed)
      parsed.each_value do |groups|
        groups.each do |candidates|
          candidates.each do |const_name|
            next if resolved_file_by_const.key?(const_name)

            resolve_constant_file(const_name)
          end
        end
      end
    end

    def resolve_dependencies(file, groups)
      deps = {}

      groups.each do |candidates|
        resolved_file = resolve_reference_group(candidates)
        next unless resolved_file
        next if resolved_file == file

        deps[resolved_file] = true
      end

      deps.empty? ? EMPTY_ARRAY : deps.keys.sort.freeze
    end

    def resolve_reference_group(candidates)
      candidates.each do |const_name|
        file = resolved_file_by_const[const_name]
        return file if file && include_path?(file)
      end

      nil
    end

    def resolve_transitive_dependencies(file)
      cached = closure_by_file[file]
      return cached if cached

      visiting = {}
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

    def resolve_constant_file(const_name)
      return nil unless constant_defined?(const_name)

      source_location = Object.const_source_location(const_name)
      file = source_location&.first
      return nil unless file && File.file?(file)

      resolved_file_by_const[const_name] = share_path(file)
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
          pattern = pattern.to_s
          pattern = File.expand_path(pattern, root) unless File.absolute_path?(pattern)
          Dir.glob(pattern)
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

    def relativize(absolute_path)
      share_string(absolute_path.delete_prefix(@root_prefix))
    end

    def relativize_input(file)
      path = file.to_s
      if File.absolute_path?(path)
        relativize(path)
      else
        share_string(path)
      end
    end

    def share_path(path)
      share_string(File.expand_path(path.to_s))
    end

    def share_string(string)
      -string.to_s
    end
  end
end
