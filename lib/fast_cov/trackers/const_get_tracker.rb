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
  # Use CoverageTracker with constant_references: true for static analysis.
  #
  # Register via: config.use FastCov::ConstGetTracker
  # Options: root, ignored_path, threads (all default from config)
  class ConstGetTracker < AbstractTracker
    def install
      Module.prepend(ConstGetPatch)
    end

    module ConstGetPatch
      def const_get(name, inherit = true)
        result = super
        FastCov::ConstGetTracker.record_const_location(self, name, inherit)
        result
      end
    end

    class << self
      def record_const_location(mod, name, inherit)
        return unless @active

        location = begin
          mod.const_source_location(name, inherit)
        rescue NameError, TypeError
          nil
        end

        return unless location&.first

        @active.record(location[0])
      end
    end
  end
end
