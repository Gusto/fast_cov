# frozen_string_literal: true

module FastCov
  class ConnectedDependencies
    CACHE_KEY = :connections
    extend ConfigurationHelper

    class << self
      def connect(owner:, dependency:)
        config = configuration

        owner_path = normalize_path(owner)
        return unless trackable_path?(owner_path, config)
        return if owner_path == dependency

        shared_owner = share_string(owner_path)
        owner_connections = cache[shared_owner] ||= {}
        owner_connections[share_string(dependency)] = true
      end

      def expand(paths)
        connections = FastCov::Cache.data[CACHE_KEY] || {}

        expanded = Set.new
        visited = {}
        queue = paths.to_a
        index = 0

        while index < queue.length
          owner = queue[index]
          index += 1
          next if visited[owner]

          visited[owner] = true
          dependencies = connections[owner] || {}

          dependencies.each_key do |dependency|
            next if paths.include?(dependency) || expanded.include?(dependency)

            expanded.add(dependency)
            queue << dependency
          end
        end

        expanded
      end

      private

      def cache
        FastCov::Cache.data[CACHE_KEY] ||= {}
      end

      def normalize_path(path)
        return if path.nil?

        File.expand_path(path.to_s)
      end

      def trackable_path?(path, config)
        return false unless path
        return false unless Utils.path_within?(path, config.root)
        return false if config.ignored_path && Utils.path_within?(path, config.ignored_path)

        true
      end

      def share_string(value)
        -value.to_s
      end
    end
  end
end
