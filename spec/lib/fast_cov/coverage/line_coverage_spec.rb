# frozen_string_literal: true

require "tmpdir"

RSpec.describe FastCov::Coverage, "line coverage" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator/operations") }

  it "clears coverage data between start/stop cycles" do
    subject.start
    expect(calculator.add(1, 2)).to eq(3)
    coverage = subject.stop
    expect(coverage.size).to eq(1)
    expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))

    subject.start
    expect(calculator.subtract(1, 2)).to eq(-1)
    coverage = subject.stop
    expect(coverage.size).to eq(1)
    expect(coverage).to include(fixtures_path("calculator/operations/subtract.rb"))
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
    expect(coverage).to include(fixtures_path("calculator/operations/multiply.rb"))
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

    expect(subject.stop).to be_empty
  end

  it "tracks coverage through prepended mixins" do
    subject.start
    expect(calculator.divide(6, 3)).to eq(2)
    coverage = subject.stop

    expect(coverage.size).to eq(2)
    expect(coverage).to include(
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

    expect(coverage).to include(
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
    expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))
  end

  context "with root scoped to the full calculator directory" do
    let(:root) { fixtures_path("calculator") }

    it "tracks the file that executes the constant access" do
      subject.start

      reader = ConstantReader.new
      expect(reader.operations).to include("add")

      coverage = subject.stop

      expect(coverage).to include(fixtures_path("calculator/operations/constant_reader.rb"))
      expect(coverage).not_to include(fixtures_path("calculator/constants.rb"))
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
    expect(coverage).to include(fixtures_path("calculator/operations/add.rb"))
  end

  describe "block form" do
    it "returns the coverage hash instead of self" do
      result = subject.start do
        calculator.add(1, 2)
        calculator.subtract(3, 1)
      end

      expect(result).to be_a(Hash)
      expect(result).to include(
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/subtract.rb")
      )
    end

    it "stops tracking after the block completes" do
      subject.start { calculator.add(1, 2) }

      # Coverage is already stopped — a new start/stop should not include add.rb
      subject.start
      calculator.multiply(2, 3)
      result = subject.stop

      expect(result).to include(fixtures_path("calculator/operations/multiply.rb"))
      expect(result).not_to include(fixtures_path("calculator/operations/add.rb"))
    end

    it "stops tracking when the block raises" do
      expect do
        subject.start do
          calculator.add(1, 2)
          raise "boom"
        end
      end.to raise_error(RuntimeError, "boom")

      subject.start
      calculator.multiply(2, 3)
      result = subject.stop

      expect(result).to include(fixtures_path("calculator/operations/multiply.rb"))
      expect(result).not_to include(fixtures_path("calculator/operations/add.rb"))
    end
  end

  describe "file identity caching" do
    # The internal seen-set starts at 256 entries and doubles as needed.
    # These specs cover the paths that only appear at scale or when execution
    # bounces between files.
    let(:file_count) { 1_500 }

    around do |example|
      Dir.mktmpdir("fast_cov_many_files") do |dir|
        @tmpdir = dir
        example.run
      end
    end

    # Method definitions rather than constants: these files get required by
    # more than one example, and redefining a constant warns.
    def write_files(dir, count)
      Array.new(count) do |i|
        path = File.join(dir, "many_files_#{i}.rb")
        File.write(path, "def many_files_#{i}\n  #{i}\nend\n")
        path
      end
    end

    it "records every file when a session touches more files than the cache holds" do
      paths = write_files(@tmpdir, file_count)
      coverage = described_class.new(root: @tmpdir)

      coverage.start
      paths.each { |path| require path }
      result = coverage.stop

      expect(result.keys).to match_array(paths)
    end

    it "clears the cache between sessions after it has grown" do
      paths = write_files(@tmpdir, file_count)
      coverage = described_class.new(root: @tmpdir)

      coverage.start
      paths.each { |path| require path }
      coverage.stop

      coverage.start
      second_result = coverage.stop

      expect(second_result).to be_empty
    end

    it "records both files when execution alternates between them" do
      root = fixtures_path("calculator")
      coverage = described_class.new(root: root)

      coverage.start
      5.times do
        calculator.add(1, 2)
        calculator.subtract(3, 1)
      end
      result = coverage.stop

      expect(result).to include(
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/subtract.rb")
      )
    end
  end
end
