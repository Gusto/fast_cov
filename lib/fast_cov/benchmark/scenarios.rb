# frozen_string_literal: true

module FastCov
  module Benchmark
    module Scenarios
      def self.register(runner, fixtures_dir:)
        root_calculator = File.join(fixtures_dir, "calculator")
        root_app = File.join(fixtures_dir, "app")
        root_all = fixtures_dir

        calculator = Calculator.new

        runner.scenario("Line coverage (small)") do
          cov = FastCov::Coverage.new(root: root_calculator, threading_mode: :multi)
          cov.start
          calculator.add(1, 2)
          calculator.subtract(3, 1)
          cov.stop
        end

        runner.scenario("Line coverage (many files)") do
          cov = FastCov::Coverage.new(root: root_all, threading_mode: :multi)
          cov.start
          calculator.add(1, 2)
          calculator.subtract(3, 1)
          calculator.multiply(2, 3)
          calculator.divide(6, 2)
          ConstantReader.new.operations
          MyModel.new
          User.new("test", "test@test.com")
          DynamicModel.new.some_method
          cov.stop
        end

        runner.scenario("Allocation tracing") do
          cov = FastCov::Coverage.new(
            root: root_app,
            threading_mode: :multi,
            allocation_tracing: true
          )
          cov.start
          MyModel.new
          User.new("test", "test@test.com")
          DynamicModel.new
          cov.stop
        end

        runner.scenario("Constant resolution (cold cache)") do
          FastCov::Cache.clear
          cov = FastCov::Coverage.new(root: root_calculator, threading_mode: :multi)
          cov.start
          ConstantReader.new.operations
          calculator.add(1, 2)
          cov.stop
        end

        runner.scenario("Constant resolution (warm cache)") do
          warm = FastCov::Coverage.new(root: root_calculator, threading_mode: :multi)
          warm.start
          ConstantReader.new.operations
          warm.stop

          cov = FastCov::Coverage.new(root: root_calculator, threading_mode: :multi)
          cov.start
          ConstantReader.new.operations
          calculator.add(1, 2)
          cov.stop
        end

        runner.scenario("Rapid start/stop (100x)") do
          cov = FastCov::Coverage.new(root: root_calculator, threading_mode: :multi)
          100.times do
            cov.start
            calculator.add(1, 2)
            cov.stop
          end
        end

        runner.scenario("Multi-threaded coverage") do
          cov = FastCov::Coverage.new(root: root_calculator, threading_mode: :multi)
          cov.start
          t = Thread.new { calculator.add(1, 2) }
          calculator.multiply(2, 3)
          t.join
          cov.stop
        end
      end
    end
  end
end
