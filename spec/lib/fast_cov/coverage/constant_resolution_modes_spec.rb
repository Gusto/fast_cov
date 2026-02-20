# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "constant resolution modes" do
  let(:root) { fixtures_path("calculator") }
  let(:constant_reader_path) { fixtures_path("calculator/operations/constant_reader.rb") }
  let(:constants_path) { fixtures_path("calculator/constants.rb") }
  let(:nested_reader_path) { fixtures_path("calculator/nested/nested_constant_reader.rb") }
  let(:nested_constant_path) { fixtures_path("calculator/nested/shared_constant.rb") }

  before { FastCov::Cache.clear }

  describe "constant_references: true (default)" do
    subject { described_class.new(root: root) }

    it "resolves constants" do
      subject.start
      ConstantReader.new.operations
      NestedFixture::Consumer::NestedConstantReader.new.value
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      expect(result.keys).to include(constants_path)
      expect(result.keys).to include(nested_reader_path)
      expect(result.keys).to include(nested_constant_path)
    end
  end

  describe "constant_references: false" do
    subject { described_class.new(root: root, constant_references: false) }

    it "does not resolve constants at all" do
      subject.start
      ConstantReader.new.operations
      NestedFixture::Consumer::NestedConstantReader.new.value
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      expect(result.keys).to include(nested_reader_path)
      # constants.rb is only discovered via constant resolution, so it should be missing
      expect(result.keys).not_to include(constants_path)
      # shared_constant.rb is only discovered via constant resolution in this setup
      expect(result.keys).not_to include(nested_constant_path)
    end
  end

  describe "constant_references: true (explicit)" do
    subject { described_class.new(root: root, constant_references: true) }

    it "resolves constants" do
      subject.start
      ConstantReader.new.operations
      NestedFixture::Consumer::NestedConstantReader.new.value
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      expect(result.keys).to include(constants_path)
      expect(result.keys).to include(nested_reader_path)
      expect(result.keys).to include(nested_constant_path)
    end
  end
end
