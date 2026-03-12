# frozen_string_literal: true

require "prism"

module FastCov
  class StaticMap
    module ReferenceExtractor
      class << self
        def extract(filename)
          result = Prism.parse_file(filename)
          raise ArgumentError, "failed to parse #{filename}" unless result.success?

          reference_groups = []
          seen_groups = {}
          collect_constants(result.value, reference_groups, seen_groups, [])

          reference_groups.map do |group|
            group.map { |const_name| -const_name }.freeze
          end.freeze
        end

        private

        def collect_constants(node, reference_groups, seen_groups, nesting_prefixes)
          case node
          when Prism::ModuleNode
            module_name = constant_name_for_nesting(node.constant_path)
            next_prefixes = next_nesting_prefixes(nesting_prefixes, module_name)
            node.body&.compact_child_nodes&.each do |child|
              collect_constants(child, reference_groups, seen_groups, next_prefixes)
            end
            return
          when Prism::ClassNode
            class_name = constant_name_for_nesting(node.constant_path)
            next_prefixes = next_nesting_prefixes(nesting_prefixes, class_name)
            add_with_nesting(node.superclass, reference_groups, seen_groups, nesting_prefixes) if node.superclass
            node.body&.compact_child_nodes&.each do |child|
              collect_constants(child, reference_groups, seen_groups, next_prefixes)
            end
            return
          when Prism::SingletonClassNode
            node.body&.compact_child_nodes&.each do |child|
              collect_constants(child, reference_groups, seen_groups, nesting_prefixes)
            end
            return
          when Prism::ConstantPathNode
            add_with_nesting(node, reference_groups, seen_groups, nesting_prefixes)
            return
          when Prism::ConstantReadNode
            add_reference_group(
              expand_with_nesting(node.name.to_s, nesting_prefixes),
              reference_groups,
              seen_groups
            )
            return
          end

          node.compact_child_nodes.each do |child|
            collect_constants(child, reference_groups, seen_groups, nesting_prefixes)
          end
        end

        def add_with_nesting(node, reference_groups, seen_groups, nesting_prefixes)
          candidates = candidates_for_node(node, nesting_prefixes)
          add_reference_group(candidates, reference_groups, seen_groups)
        end

        def candidates_for_node(node, nesting_prefixes)
          case node
          when Prism::ConstantPathNode
            path = resolve_constant_path(node)
            return FastCov::StaticMap::EMPTY_ARRAY unless path

            if path.start_with?("::")
              [path.delete_prefix("::")]
            else
              expand_with_nesting(path, nesting_prefixes)
            end
          when Prism::ConstantReadNode
            expand_with_nesting(node.name.to_s, nesting_prefixes)
          else
            FastCov::StaticMap::EMPTY_ARRAY
          end
        end

        def add_reference_group(candidates, reference_groups, seen_groups)
          return if candidates.empty?

          key = candidates.join("\0")
          return if seen_groups[key]

          seen_groups[key] = true
          reference_groups << candidates
        end

        def expand_with_nesting(const_name, nesting_prefixes)
          candidates = []
          seen_candidates = {}

          nesting_prefixes.reverse_each do |prefix|
            add_unique("#{prefix}::#{const_name}", candidates, seen_candidates)
          end

          add_unique(const_name, candidates, seen_candidates)
          candidates
        end

        def next_nesting_prefixes(nesting_prefixes, nested_name)
          return nesting_prefixes unless nested_name

          if nesting_prefixes.empty?
            [nested_name]
          else
            nesting_prefixes + ["#{nesting_prefixes.last}::#{nested_name}"]
          end
        end

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
            return "::#{parts.join("::")}"
          else
            return nil
          end

          parts.join("::")
        end
      end
    end
  end
end
