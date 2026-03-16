# frozen_string_literal: true

require "set"
require "thread"

module FastCov
  class ConnectedDependencies
    def initialize(coverage_map)
      @coverage_map = coverage_map
      @connections = {}
      @mutex = Mutex.new
    end

    def connect(from:, to:)
      source = normalize_path(from)
      return unless source
      return unless @coverage_map.include_path?(source)
      return if source == to

      @mutex.synchronize do
        (@connections[source] ||= {})[to] = true
      end
    end

    def expand(paths)
      raise ArgumentError, "paths must be a Set" unless paths.is_a?(Set)

      pending_paths = paths.to_a

      until pending_paths.empty?
        path = pending_paths.pop

        connections = @connections[path]
        next unless connections

        connections.each_key do |dependency|
          next unless paths.add?(dependency)

          pending_paths << dependency
        end
      end

      paths
    end

    private

    def normalize_path(path)
      return if path.nil?

      File.expand_path(path.to_s)
    end
  end
end
