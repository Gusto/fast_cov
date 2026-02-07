# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "path filtering" do
  include_context "coverage instance"

  context "when root matches the full project directory" do
    let(:root) { fixtures_path("calculator") }

    it "collects coverage for all files under root" do
      subject.start

      expect(calculator.add(1, 2)).to eq(3)
      expect(calculator.subtract(1, 2)).to eq(-1)

      coverage = subject.stop

      # Line events track the executed files directly, and constant
      # resolution discovers additional files referenced via constants
      # (e.g., calculator.rb references Add, Subtract, Multiply, Divide).
      expect(coverage.keys).to include(
        fixtures_path("calculator/calculator.rb"),
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/subtract.rb")
      )
    end

    context "with an ignored_path set" do
      let(:ignored_path) { fixtures_path("calculator/operations") }

      it "excludes files under the ignored path" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(
          fixtures_path("calculator/calculator.rb")
        )
      end
    end

    context "when ignored_path equals root" do
      let(:ignored_path) { fixtures_path("calculator") }

      it "collects no coverage since everything is ignored" do
        subject.start

        expect(calculator.add(1, 2)).to eq(3)
        expect(calculator.subtract(1, 2)).to eq(-1)

        coverage = subject.stop

        expect(coverage).to be_empty
      end
    end
  end

  context "when root points to a nonexistent subdirectory" do
    let(:root) { fixtures_path("calculator/operations/suboperations") }

    it "collects no coverage" do
      subject.start

      expect(calculator.add(1, 2)).to eq(3)
      expect(calculator.subtract(1, 2)).to eq(-1)

      coverage = subject.stop

      expect(coverage.size).to eq(0)
    end
  end

  context "when root is scoped to a subdirectory" do
    let(:root) { fixtures_path("calculator/operations") }

    it "only collects coverage for files under that subdirectory" do
      subject.start

      expect(calculator.add(1, 2)).to eq(3)
      expect(calculator.subtract(1, 2)).to eq(-1)

      coverage = subject.stop

      expect(coverage.size).to eq(2)
      expect(coverage.keys).to include(
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/subtract.rb")
      )
    end
  end
end
