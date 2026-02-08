# frozen_string_literal: true

require "prism"

module FastCov
  module ConstantExtractor
    def self.extract(filename)
      result = Prism.parse_file(filename)
      constants = []
      collect_constants(result.value, constants)
      constants
    end

    class << self
      private

      def collect_constants(node, constants)
        case node
        when Prism::ConstantPathNode
          path = resolve_constant_path(node)
          if path
            constants << path
            return
          end
          # Dynamic parent (e.g., expr::Foo) — fall through to walk children
        when Prism::ConstantReadNode
          constants << node.name.to_s
          return
        end

        node.compact_child_nodes.each { |child| collect_constants(child, constants) }
      end

      def resolve_constant_path(node)
        parts = []
        current = node

        while current.is_a?(Prism::ConstantPathNode)
          parts.unshift(current.name.to_s)
          current = current.parent
        end

        if current.is_a?(Prism::ConstantReadNode)
          parts.unshift(current.name.to_s)
        elsif !current.nil?
          return nil
        end

        parts.join("::")
      end
    end
  end
end
