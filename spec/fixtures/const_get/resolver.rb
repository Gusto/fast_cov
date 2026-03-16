# frozen_string_literal: true

module ConstGetFixtures
  class Resolver
    def resolve(name)
      @resolved_constants ||= {}
      @resolved_constants[name] ||= ConstGetFixtures.const_get(name)
    end

    def reset!
      remove_instance_variable(:@resolved_constants) if instance_variable_defined?(:@resolved_constants)
    end
  end
end
