# frozen_string_literal: true

module ConstGetFixtures
  class Resolver
    class << self
      def service_class
        @service_class ||= ConstGetFixtures.const_get(:Service)
      end

      def reset
        @service_class = nil
      end
    end
  end
end
