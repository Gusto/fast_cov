# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "robustness" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator/operations") }

  it "survives GC stress during line coverage" do
    subject.start

    10_000.times do |i|
      calculator.add(1, 2)
      GC.start(full_mark: true, immediate_sweep: true) if i % 100 == 0
    end

    coverage = subject.stop
    expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))
  end

  it "handles BasicObject subclasses without crashing" do
    klass = Class.new(BasicObject) do
      def initialize
      end
    end

    subject.start

    klass.new
    calculator.add(1, 2)

    coverage = subject.stop
    expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))
  end

  it "handles anonymous classes without crashing" do
    subject.start

    calculator.add(1, 2)
    c = Class.new(Object) {}
    c.new

    coverage = subject.stop
    expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))
  end

  it "handles many rapid start/stop cycles" do
    100.times do
      subject.start
      calculator.add(1, 2)
      coverage = subject.stop
      expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))
    end
  end
end
