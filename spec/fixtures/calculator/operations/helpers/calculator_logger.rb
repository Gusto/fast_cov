# frozen_string_literal: true

module CalculatorLogger
  def call(*)
    result = super
    @log ||= []
    @log << "operation performed"
    result
  end
end
