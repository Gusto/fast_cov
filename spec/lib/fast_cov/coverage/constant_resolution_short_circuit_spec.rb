# frozen_string_literal: true

require "tmpdir"

RSpec.describe FastCov::Coverage, "constant reference short-circuiting" do
  it "stops at first resolvable lexical candidate" do
    Dir.mktmpdir("fast_cov_short_circuit") do |tmp_root|
      root = File.realpath(tmp_root)
      namespaced_top_shared = File.join(root, "namespaced_top_shared.rb")
      top_shared = File.join(root, "top_shared.rb")
      runner = File.join(root, "runner.rb")

      File.write(namespaced_top_shared, <<~RUBY)
        # frozen_string_literal: true

        module FastCovShortCircuitFixture
          module TopShared
            VALUE = "namespaced"
          end
        end
      RUBY

      File.write(top_shared, <<~RUBY)
        # frozen_string_literal: true

        module TopShared
          VALUE = "top_level"
        end
      RUBY

      File.write(runner, <<~RUBY)
        # frozen_string_literal: true

        require_relative "namespaced_top_shared"
        require_relative "top_shared"

        module FastCovShortCircuitFixture
          module Consumer
            class Runner
              def run
                TopShared::VALUE
              end
            end
          end
        end
      RUBY

      load runner

      coverage = described_class.new(root: root, allocations: false)
      coverage.start
      expect(FastCovShortCircuitFixture::Consumer::Runner.new.run).to eq("namespaced")
      result = coverage.stop

      expect(result.keys).to include(runner)
      expect(result.keys).to include(namespaced_top_shared)
      expect(result.keys).not_to include(top_shared)
    end
  end
end
