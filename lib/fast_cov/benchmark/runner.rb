# frozen_string_literal: true

require "json"
require "fileutils"

module FastCov
  module Benchmark
    class Runner
      DEFAULT_ITERATIONS = 1000
      DEFAULT_SAMPLES = 7
      WARMUP_ITERATIONS = 20

      attr_reader :iterations, :samples, :baseline_path

      def initialize(iterations: DEFAULT_ITERATIONS, samples: DEFAULT_SAMPLES, baseline_path: nil)
        @iterations = iterations
        @samples = samples
        @baseline_path = baseline_path || default_baseline_path
        @scenarios = []
      end

      def scenario(name, &block)
        @scenarios << { name: name, block: block }
      end

      def run(save_baseline: false)
        baseline = load_baseline unless save_baseline
        results = run_scenarios

        print_results(results, baseline)

        if save_baseline
          save_baseline_to_disk(results)
        elsif baseline
          puts "Baseline: #{@baseline_path} (saved #{baseline["saved_at"]})"
        else
          puts "No baseline found. Run with --baseline to save one."
        end
      end

      private

      def run_scenarios
        results = {}

        @scenarios.each do |scenario|
          measurement = measure(scenario[:block])
          results[scenario[:name]] = measurement
        end

        results
      end

      def measure(block)
        # Warmup: let JIT, caches, and memory settle
        WARMUP_ITERATIONS.times { block.call }

        # Collect multiple samples, take the median to filter outliers
        elapsed_samples = Array.new(@samples) do
          GC.start
          GC.compact

          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @iterations.times { block.call }
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        end

        median_elapsed = median(elapsed_samples)

        {
          "avg_ms" => (median_elapsed / @iterations) * 1000.0,
          "ips" => @iterations / median_elapsed
        }
      end

      def median(values)
        sorted = values.sort
        mid = sorted.length / 2
        if sorted.length.odd?
          sorted[mid]
        else
          (sorted[mid - 1] + sorted[mid]) / 2.0
        end
      end

      def print_results(results, baseline)
        has_baseline = baseline && baseline["results"]

        puts "FastCov Benchmark Suite"
        puts "Ruby #{RUBY_VERSION}, #{RUBY_PLATFORM}"
        puts "#{@iterations} iterations x #{@samples} samples (median)"
        puts "=" * 72
        puts

        header = format("  %-38s %10s %12s", "", "avg (ms)", "ips")
        header += format(" %14s", "vs baseline") if has_baseline
        puts header
        puts "-" * header.length

        results.each do |name, result|
          line = format("  %-38s %10.3f %12.1f", name, result["avg_ms"], result["ips"])

          if has_baseline && (base = baseline["results"][name])
            base_avg = base["avg_ms"]
            if base_avg > 0
              delta_pct = ((result["avg_ms"] - base_avg) / base_avg) * 100.0
              sign = delta_pct >= 0 ? "+" : ""
              line += format(" %13s", "#{sign}#{"%.1f" % delta_pct}%")
            end
          end

          puts line
        end

        puts
      end

      def load_baseline
        return nil unless File.exist?(@baseline_path)

        JSON.parse(File.read(@baseline_path))
      rescue JSON::ParserError
        nil
      end

      def save_baseline_to_disk(results)
        FileUtils.mkdir_p(File.dirname(@baseline_path))

        payload = {
          "saved_at" => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
          "ruby_version" => RUBY_VERSION,
          "platform" => RUBY_PLATFORM,
          "iterations" => @iterations,
          "samples" => @samples,
          "results" => results
        }

        File.write(@baseline_path, JSON.pretty_generate(payload))
        puts "Baseline saved to #{@baseline_path}"
      end

      def default_baseline_path
        File.expand_path("tmp/benchmark_baseline.json", Dir.pwd)
      end
    end
  end
end
