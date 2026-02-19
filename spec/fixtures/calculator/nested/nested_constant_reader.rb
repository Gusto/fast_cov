# frozen_string_literal: true

require_relative "shared_constant"

module NestedFixture
  module Consumer
    class NestedConstantReader
      def value
        SharedConstant::VALUE
      end
    end
  end
end
