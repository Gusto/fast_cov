# frozen_string_literal: true

module FastCov
  module Benchmark
    module Scenarios
      def self.register(runner, fixtures_dir:)
        root_calculator = File.join(fixtures_dir, "calculator")
        root_all = fixtures_dir
        ignored_path = File.join(fixtures_dir, "vendor")

        calculator = Calculator.new

        runner.scenario("Line coverage (small)") do
          cov = FastCov::Coverage.new(root: root_calculator)
          cov.start
          calculator.add(1, 2)
          calculator.subtract(3, 1)
          cov.stop
        end

        runner.scenario("Line coverage (many files)") do
          cov = FastCov::Coverage.new(root: root_all)
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

        runner.scenario("Line coverage (single-threaded)") do
          cov = FastCov::Coverage.new(root: root_calculator, threads: false)
          cov.start
          calculator.add(1, 2)
          calculator.subtract(3, 1)
          cov.stop
        end

        runner.scenario("Line coverage (with ignored_path)") do
          cov = FastCov::Coverage.new(root: root_all, ignored_paths: [ignored_path])
          cov.start
          calculator.add(1, 2)
          calculator.subtract(3, 1)
          cov.stop
        end

        runner.scenario("Rapid start/stop (100x)") do
          cov = FastCov::Coverage.new(root: root_calculator)
          100.times do
            cov.start
            calculator.add(1, 2)
            cov.stop
          end
        end

        runner.scenario("Multi-threaded coverage") do
          cov = FastCov::Coverage.new(root: root_calculator)
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
