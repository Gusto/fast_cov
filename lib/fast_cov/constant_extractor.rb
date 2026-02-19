# frozen_string_literal: true

require "prism"

module FastCov
  # Extracts constant references from Ruby source files using Prism.
  module ConstantExtractor
    def self.extract(filename)
      result = Prism.parse_file(filename)
      constants = []
      seen = {}
      collect_constants_expanded(result.value, constants, seen, [])

      constants
    end

    class << self
      private

      # Expanded mode: track nesting and expand bare constants
      def collect_constants_expanded(node, constants, seen, nesting_prefixes)
        case node
        when Prism::ModuleNode
          module_name = constant_name_for_nesting(node.constant_path)
          next_prefixes = next_nesting_prefixes(nesting_prefixes, module_name)
          node.body&.compact_child_nodes&.each do |child|
            collect_constants_expanded(child, constants, seen, next_prefixes)
          end
          return

        when Prism::ClassNode
          class_name = constant_name_for_nesting(node.constant_path)
          next_prefixes = next_nesting_prefixes(nesting_prefixes, class_name)
          # Superclass is a reference, add it
          if node.superclass
            add_with_nesting(node.superclass, constants, seen, nesting_prefixes)
          end
          node.body&.compact_child_nodes&.each do |child|
            collect_constants_expanded(child, constants, seen, next_prefixes)
          end
          return

        when Prism::SingletonClassNode
          # class << self - nesting doesn't change
          node.body&.compact_child_nodes&.each do |child|
            collect_constants_expanded(child, constants, seen, nesting_prefixes)
          end
          return

        when Prism::ConstantPathNode
          add_with_nesting(node, constants, seen, nesting_prefixes)
          return

        when Prism::ConstantReadNode
          # Bare constant - expand with all possible nestings
          expand_with_nesting(node.name.to_s, constants, seen, nesting_prefixes)
          return
        end

        node.compact_child_nodes.each do |child|
          collect_constants_expanded(child, constants, seen, nesting_prefixes)
        end
      end

      def add_with_nesting(node, constants, seen, nesting_prefixes)
        case node
        when Prism::ConstantPathNode
          path = resolve_constant_path(node)
          return unless path

          if path.start_with?("::")
            # Absolute path like ::Foo::Bar - add without leading ::
            add_unique(path.delete_prefix("::"), constants, seen)
          else
            # Relative path like Foo::Bar - the first part gets nesting expansion
            expand_with_nesting(path, constants, seen, nesting_prefixes)
          end
        when Prism::ConstantReadNode
          expand_with_nesting(node.name.to_s, constants, seen, nesting_prefixes)
        end
      end

      def expand_with_nesting(const_name, constants, seen, nesting_prefixes)
        # Always add the constant as-is (could be top-level or fully qualified)
        add_unique(const_name, constants, seen)

        # Add with each level of nesting (from current to outermost)
        nesting_prefixes.reverse_each do |prefix|
          add_unique("#{prefix}::#{const_name}", constants, seen)
        end
      end

      def next_nesting_prefixes(nesting_prefixes, nested_name)
        return nesting_prefixes unless nested_name

        if nesting_prefixes.empty?
          [nested_name]
        else
          nesting_prefixes + ["#{nesting_prefixes[-1]}::#{nested_name}"]
        end
      end

      # Extract the constant name/path for nesting tracking
      def constant_name_for_nesting(node)
        case node
        when Prism::ConstantPathNode
          resolve_constant_path(node)&.delete_prefix("::")
        when Prism::ConstantReadNode
          node.name.to_s
        end
      end

      def add_unique(const_name, constants, seen)
        return if seen[const_name]

        seen[const_name] = true
        constants << const_name
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
