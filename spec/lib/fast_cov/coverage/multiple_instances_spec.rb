# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "multiple instances" do
  let(:root) { fixtures_path("calculator") }
  let!(:calculator) { Calculator.new }

  describe "overlapping sessions" do
    # Event hooks are removed by matching both the callback and the object that
    # registered it. Matching on the callback alone would tear down every live
    # instance's hook, and the surviving instances would go on reporting
    # success while recording nothing.
    it "keeps the outer session recording after an inner session stops" do
      outer = described_class.new(root: root)
      inner = described_class.new(root: root)

      outer.start
      calculator.add(1, 2)

      inner.start
      calculator.subtract(3, 1)
      inner.stop

      # Executed only after the inner session stopped, so it is the file that
      # proves the outer session still has a live hook.
      calculator.multiply(2, 3)
      result = outer.stop

      expect(result).to include(fixtures_path("calculator/operations/multiply.rb"))
    end

    it "records into each session independently" do
      outer = described_class.new(root: root)
      inner = described_class.new(root: root)

      outer.start
      calculator.add(1, 2)

      inner.start
      calculator.subtract(3, 1)
      inner_result = inner.stop

      outer_result = outer.stop

      expect(inner_result).to include(fixtures_path("calculator/operations/subtract.rb"))
      expect(inner_result).not_to include(fixtures_path("calculator/operations/add.rb"))
      expect(outer_result).to include(
        fixtures_path("calculator/operations/add.rb"),
        fixtures_path("calculator/operations/subtract.rb")
      )
    end

    it "leaves no hook installed once every session has stopped" do
      first = described_class.new(root: root)
      second = described_class.new(root: root)

      first.start
      second.start
      calculator.add(1, 2)
      second.stop
      first.stop

      # A hook that outlived its session would keep recording here.
      calculator.divide(6, 3)

      third = described_class.new(root: root)
      third.start
      calculator.subtract(3, 1)
      result = third.stop

      expect(result).to include(fixtures_path("calculator/operations/subtract.rb"))
      expect(result).not_to include(fixtures_path("calculator/operations/divide.rb"))
    end
  end
end
