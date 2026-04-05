# frozen_string_literal: true

module FastCov
  class StaticMap
    EMPTY_ARRAY = [].freeze

    autoload :ReferenceExtractor, "fast_cov/static_map/reference_extractor"

    def initialize(root:, ignored_paths: [], concurrency: Etc.nprocessors)
      @root = share_path(root)
      @root_prefix = -"#{@root}/"
      @ignored_paths = normalize_ignored_paths(ignored_paths)
      @concurrency = concurrency
      @resolved_file_by_const = {}
      @resolve_mutex = Mutex.new
      @direct_dependencies_by_file = {}
      @deps_mutex = Mutex.new
      @closure_by_file = {}
      @graph = {}
    end

    def build(*patterns)
      input_files = expand_files(patterns.flatten).select { |file| processable_file?(file) }

      if @concurrency > 1
        build_parallel(input_files)
      else
        build_sequential(input_files)
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

    attr_reader :closure_by_file, :direct_dependencies_by_file, :ignored_paths,
                :resolved_file_by_const, :root

    def build_sequential(input_files)
      queue = input_files.dup
      processed = {}
      index = 0

      while index < queue.length
        file = queue[index]
        index += 1
        next if processed[file]

        processed[file] = true
        deps = direct_dependencies_for_file(file)
        store_graph_entry(file, deps)

        deps.each do |dep|
          next if processed[dep]
          next unless processable_file?(dep)

          queue << dep
        end
      end
    end

    def build_parallel(input_files)
      queue = Queue.new
      processed = {}
      processed_mutex = Mutex.new
      discovered = Queue.new

      input_files.each { |f| queue << f }

      loop do
        break if queue.empty?

        # Drain queue into a batch for this round
        batch = []
        batch << queue.pop until queue.empty?

        # Filter already-processed files
        batch.reject! do |file|
          processed_mutex.synchronize { processed[file] }
        end
        next if batch.empty?

        # Process batch in parallel
        results = batch.each_slice(([batch.size / @concurrency, 1].max)).map do |slice|
          Thread.new(slice) do |files|
            thread_results = []
            files.each do |file|
              skip = processed_mutex.synchronize do
                if processed[file]
                  true
                else
                  processed[file] = true
                  false
                end
              end
              next if skip

              deps = direct_dependencies_for_file(file)
              thread_results << [file, deps]
            end
            thread_results
          end
        end.flat_map(&:value)

        # Store results and discover new files (sequential — fast)
        results.each do |file, deps|
          store_graph_entry(file, deps)

          deps.each do |dep|
            next if processed_mutex.synchronize { processed[dep] }
            next unless processable_file?(dep)

            queue << dep
          end
        end
      end
    end

    def store_graph_entry(file, deps)
      relative_file = relativize(file)
      @graph[relative_file] = deps.empty? ? EMPTY_ARRAY : deps.map { |d| relativize(d) }.freeze
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

      resolved = share_path(file)
      @resolve_mutex.synchronize { resolved_file_by_const[shared_const_name] = resolved }
      resolved
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
      cached = @deps_mutex.synchronize { direct_dependencies_by_file[file] }
      return cached if cached

      dependencies = {}

      reference_groups_for(file).each do |candidates|
        resolved_file = resolve_reference_group(candidates)
        next unless resolved_file
        next unless include_path?(resolved_file)

        dependencies[resolved_file] = true
      end

      dependencies.delete(file)
      result = dependencies.empty? ? EMPTY_ARRAY : dependencies.keys.sort.freeze
      @deps_mutex.synchronize { direct_dependencies_by_file[file] = result }
      result
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
