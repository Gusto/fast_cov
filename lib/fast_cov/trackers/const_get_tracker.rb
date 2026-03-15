# frozen_string_literal: true

require_relative "abstract_tracker"

module FastCov
  # Tracks constants looked up dynamically via Module#const_get.
  #
  # This catches dynamic constant lookups that static analysis misses:
  # - Object.const_get("Foo::Bar")
  # - Rails' "UserMailer".constantize (uses const_get under the hood)
  # - Any metaprogramming that looks up constants by string name
  #
  # Note: This does NOT catch direct constant references like `Foo::Bar` in source
  # code - those compile to opt_getconstant_path bytecode and bypass const_get.
  #
  # Register via: coverage_map.use(FastCov::ConstGetTracker)
  class ConstGetTracker < AbstractTracker
    def install
      return if Module.ancestors.include?(ConstGetPatch)

      Module.prepend(ConstGetPatch)
    end

    module ConstGetPatch
      def const_get(name, inherit = true)
        result = super
        FastCov::ConstGetTracker.record do
          location = self.const_source_location(name, inherit) rescue nil
          location&.first
        end
        result
      end
    end
  end
end
