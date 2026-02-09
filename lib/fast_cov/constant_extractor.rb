# frozen_string_literal: true

require "prism"

module FastCov
  # Extracts constant references from Ruby source files using Prism.
  #
  # Supports two modes:
  # - :simple - extracts constants as-is (e.g., `Foo` -> ["Foo"])
  # - :expanded - expands bare constants with all possible nesting resolutions
  #   (e.g., `Foo` inside `module A; class B` -> ["Foo", "B::Foo", "A::B::Foo", "A::Foo"])
  module ConstantExtractor
    def self.extract(filename, mode = :expanded)
      result = Prism.parse_file(filename)
      constants = []

      case mode
      when :simple
        collect_constants_simple(result.value, constants)
      when :expanded
        collect_constants_expanded(result.value, constants, [])
        constants.uniq!
      else
        raise ArgumentError, "Unknown mode: #{mode.inspect}. Use :simple or :expanded"
      end

      constants
    end

    class << self
      private

      # Simple mode: extract constants without nesting expansion
      def collect_constants_simple(node, constants)
        case node
        when Prism::ConstantPathNode
          path = resolve_constant_path(node)
          if path
            constants << path.delete_prefix("::")
            return
          end
          # Dynamic parent (e.g., expr::Foo) — fall through to walk children
        when Prism::ConstantReadNode
          constants << node.name.to_s
          return
        end

        node.compact_child_nodes.each { |child| collect_constants_simple(child, constants) }
      end

      # Expanded mode: track nesting and expand bare constants
      def collect_constants_expanded(node, constants, nesting)
        case node
        when Prism::ModuleNode
          module_name = constant_name_for_nesting(node.constant_path)
          new_nesting = module_name ? nesting + [module_name] : nesting
          node.body&.compact_child_nodes&.each { |child| collect_constants_expanded(child, constants, new_nesting) }
          return

        when Prism::ClassNode
          class_name = constant_name_for_nesting(node.constant_path)
          new_nesting = class_name ? nesting + [class_name] : nesting
          # Superclass is a reference, add it
          if node.superclass
            add_with_nesting(node.superclass, constants, nesting)
          end
          node.body&.compact_child_nodes&.each { |child| collect_constants_expanded(child, constants, new_nesting) }
          return

        when Prism::SingletonClassNode
          # class << self - nesting doesn't change
          node.body&.compact_child_nodes&.each { |child| collect_constants_expanded(child, constants, nesting) }
          return

        when Prism::ConstantPathNode
          add_with_nesting(node, constants, nesting)
          return

        when Prism::ConstantReadNode
          # Bare constant - expand with all possible nestings
          expand_with_nesting(node.name.to_s, constants, nesting)
          return
        end

        node.compact_child_nodes.each { |child| collect_constants_expanded(child, constants, nesting) }
      end

      def add_with_nesting(node, constants, nesting)
        case node
        when Prism::ConstantPathNode
          path = resolve_constant_path(node)
          if path
            if path.start_with?("::")
              # Absolute path like ::Foo::Bar - add without leading ::
              constants << path[2..]
            else
              # Relative path like Foo::Bar - the first part gets nesting expansion
              expand_with_nesting(path, constants, nesting)
            end
          end
        when Prism::ConstantReadNode
          expand_with_nesting(node.name.to_s, constants, nesting)
        end
      end

      def expand_with_nesting(const_name, constants, nesting)
        # Always add the constant as-is (could be top-level or fully qualified)
        constants << const_name

        # Add with each level of nesting (from current to outermost)
        nesting.size.times do |i|
          prefix = nesting[0..-(i + 1)].join("::")
          constants << "#{prefix}::#{const_name}"
        end
      end

      # Extract the constant name/path for nesting tracking
      def constant_name_for_nesting(node)
        case node
        when Prism::ConstantPathNode
          resolve_constant_path(node)
        when Prism::ConstantReadNode
          node.name.to_s
        end
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
        elsif current.nil?
          # Absolute path like ::Foo
          return "::" + parts.join("::")
        else
          return nil
        end

        parts.join("::")
      end
    end
  end
end
