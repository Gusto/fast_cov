# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "line coverage" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator/operations") }

  it "clears coverage data between start/stop cycles" do
    subject.start
    expect(calculator.add(1, 2)).to eq(3)
    coverage = subject.stop
    expect(coverage.size).to eq(1)
    expect(coverage.keys).to include(fixtures_path("calculator/operations/add.rb"))

    subject.start
    expect(calculator.subtract(1, 2)).to eq(-1)
    coverage = subject.stop
    expect(coverage.size).to eq(1)
    expect(coverage.keys).to include(fixtures_path("calculator/operations/subtract.rb"))
  end

  it "does not track coverage when stopped" do
    subject.start
    expect(calculator.add(1, 2)).to eq(3)
    subject.stop

    # this execution happens while stopped — should not be tracked
    expect(calculator.subtract(1, 2)).to eq(-1)

    subject.start
    expect(calculator.multiply(1, 2)).to eq(2)
    coverage = subject.stop
    expect(coverage.size).to eq(1)
    expect(coverage.keys).to include(fixtures_path("calculator/operations/multiply.rb"))
  end

  it "does not fail if start is called several times" do
    subject.start
    expect(calculator.add(1, 2)).to eq(3)

    subject.start
    coverage = subject.stop
    expect(coverage.size).to eq(1)
  end

  it "does not fail if stop is called several times" do
    subject.start
    expect(calculator.add(1, 2)).to eq(3)
    coverage = subject.stop
    expect(coverage.size).to eq(1)

    expect(subject.stop).to eq({})
  end

  it "tracks coverage through prepended mixins" do
    subject.start
    expect(calculator.divide(6, 3)).to eq(2)
    coverage = subject.stop

    expect(coverage.size).to eq(2)
    expect(coverage.keys).to include(
      fixtures_path("calculator/operations/divide.rb"),
      fixtures_path("calculator/operations/helpers/calculator_logger.rb")
    )
  end

  it "tracks coverage for code that raises exceptions" do
    subject.start

    begin
      calculator.divide(1, 0)
    rescue ZeroDivisionError
    end

    coverage = subject.stop

    expect(coverage.keys).to include(
      fixtures_path("calculator/operations/divide.rb"),
      fixtures_path("calculator/operations/helpers/calculator_logger.rb")
    )
  end

  it "handles eval'd code without crashing" do
    subject.start

    eval("1 + 1", binding, __FILE__, __LINE__)
    eval("def dynamic_method_from_eval; 42; end", binding, __FILE__, __LINE__)
    dynamic_method_from_eval

    expect(calculator.add(1, 2)).to eq(3)

    coverage = subject.stop
    expect(coverage.keys).to include(fixtures_path("calculator/operations/add.rb"))
  end

  context "with root scoped to the full calculator directory" do
    let(:root) { fixtures_path("calculator") }

    it "tracks both the file that accesses a constant and the file that defines it" do
      subject.start

      reader = ConstantReader.new
      expect(reader.operations).to include("add")

      coverage = subject.stop

      expect(coverage.keys).to include(
        fixtures_path("calculator/operations/constant_reader.rb"),
        fixtures_path("calculator/constants.rb")
      )
    end
  end

  it "handles dynamically defined methods via define_method" do
    klass = Class.new do
      define_method(:dynamic_add) do |a, b|
        a + b
      end
    end

    subject.start

    result = klass.new.dynamic_add(1, 2)
    expect(result).to eq(3)

    expect(calculator.add(1, 2)).to eq(3)

    coverage = subject.stop
    expect(coverage.keys).to include(fixtures_path("calculator/operations/add.rb"))
  end
end
