# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "threading" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator/operations") }

  describe "single threaded mode" do
    let(:threading_mode) { :single }
    let(:use_allocation_tracing) { false }

    it "isolates coverage to each thread independently" do
      t1_queue = Thread::Queue.new
      t2_queue = Thread::Queue.new

      t1 = Thread.new do
        cov = described_class.new(
          root: root,
          threading_mode: :single,
          use_allocation_tracing: false
        )
        cov.start

        t1_queue << :ready
        expect(t2_queue.pop).to be(:ready)

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.multiply(1, 2)).to eq(2)

        t1_queue << :done
        expect(t2_queue.pop).to be(:done)

        coverage = cov.stop
        expect(coverage.size).to eq(2)
        expect(coverage.keys).to include(
          fixtures_path("calculator/operations/add.rb"),
          fixtures_path("calculator/operations/multiply.rb")
        )
      end

      t2 = Thread.new do
        cov = described_class.new(
          root: root,
          threading_mode: :single,
          use_allocation_tracing: false
        )
        cov.start

        t2_queue << :ready
        expect(t1_queue.pop).to be(:ready)

        expect(calculator.subtract(1, 2)).to eq(-1)

        t2_queue << :done
        expect(t1_queue.pop).to be(:done)

        coverage = cov.stop
        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(
          fixtures_path("calculator/operations/subtract.rb")
        )
      end

      [t1, t2].each(&:join)
    end
  end

  describe "multi threaded mode" do
    let(:threading_mode) { :multi }

    it "collects coverage from background threads" do
      subject.start

      t = Thread.new do
        expect(calculator.add(1, 2)).to eq(3)
      end

      expect(calculator.multiply(1, 2)).to eq(2)
      t.join

      coverage = subject.stop
      expect(coverage.size).to eq(2)
      expect(coverage.keys).to include(
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/multiply.rb")
      )
    end

    it "collects coverage from threads that were started before collection began" do
      jobs_queue = Thread::Queue.new
      background_worker = Thread.new do
        loop do
          job = jobs_queue.pop
          break if job == :done

          job.call
        end
      end

      cov = described_class.new(root: root, threading_mode: :multi)
      cov.start

      jobs_queue << -> { expect(calculator.add(1, 2)).to eq(3) }
      jobs_queue << -> { expect(calculator.multiply(1, 2)).to eq(2) }
      jobs_queue << :done

      background_worker.join

      coverage = cov.stop
      expect(coverage.size).to eq(2)
      expect(coverage.keys).to include(
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/multiply.rb")
      )
    end

    it "does not track coverage when stopped" do
      subject.start
      expect(calculator.add(1, 2)).to eq(3)
      subject.stop

      expect(calculator.subtract(1, 2)).to eq(-1)

      subject.start
      expect(calculator.multiply(1, 2)).to eq(2)
      coverage = subject.stop
      expect(coverage.size).to eq(1)
      expect(coverage.keys).to include(
        fixtures_path("calculator/operations/multiply.rb")
      )
    end
  end
end
