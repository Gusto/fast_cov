# frozen_string_literal: true

module FastCov
  class ConnectedDependencies
    def initialize
      @connections = {}
      @mutex = Mutex.new
    end

    def connect(from:, to:)
      @mutex.synchronize do
        (@connections[from] ||= {})[to] = true
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
  end
end
