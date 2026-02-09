# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "constant resolution modes" do
  let(:root) { fixtures_path("calculator") }
  let(:constant_reader_path) { fixtures_path("calculator/operations/constant_reader.rb") }
  let(:constants_path) { fixtures_path("calculator/constants.rb") }

  before { FastCov::Cache.clear }

  describe "constant_references: :expanded (default)" do
    subject { described_class.new(root: root) }

    it "resolves constants with nesting expansion" do
      subject.start
      ConstantReader.new.operations
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      expect(result.keys).to include(constants_path)
    end
  end

  describe "constant_references: :simple" do
    subject { described_class.new(root: root, constant_references: :simple) }

    it "resolves constants without nesting expansion" do
      subject.start
      ConstantReader.new.operations
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      expect(result.keys).to include(constants_path)
    end
  end

  describe "constant_references: false" do
    subject { described_class.new(root: root, constant_references: false) }

    it "does not resolve constants at all" do
      subject.start
      ConstantReader.new.operations
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      # constants.rb is only discovered via constant resolution, so it should be missing
      expect(result.keys).not_to include(constants_path)
    end
  end

  describe "constant_references: true (legacy, defaults to :expanded)" do
    subject { described_class.new(root: root, constant_references: true) }

    it "resolves constants with nesting expansion" do
      subject.start
      ConstantReader.new.operations
      result = subject.stop

      expect(result.keys).to include(constant_reader_path)
      expect(result.keys).to include(constants_path)
    end
  end
end
