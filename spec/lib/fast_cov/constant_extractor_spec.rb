# frozen_string_literal: true

RSpec.describe FastCov::ConstantExtractor do
  describe ".extract" do
    it "returns nested candidates from most-specific to least-specific" do
      groups = described_class.extract(fixtures_path("calculator/nested/nested_constant_reader.rb"))

      expect(groups).to include(
        [
          "NestedFixture::Consumer::NestedConstantReader::SharedConstant::VALUE",
          "NestedFixture::Consumer::SharedConstant::VALUE",
          "NestedFixture::SharedConstant::VALUE",
          "SharedConstant::VALUE"
        ]
      )
    end
  end
end
