# frozen_string_literal: true

require "tempfile"

RSpec.describe FastCov::StaticMap::ReferenceExtractor do
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

    it "treats fully-qualified ::Constants as a single candidate" do
      with_tempfile("::TopLevel::Foo\n") do |path|
        groups = described_class.extract(path)

        expect(groups).to include(["TopLevel::Foo"])
      end
    end

    it "handles compact class definitions without intermediate nesting" do
      with_tempfile(<<~RUBY) do |path|
        module Outer
          class Inner::Deep
            Ref
          end
        end
      RUBY
        groups = described_class.extract(path)

        # Should NOT include Outer::Inner::Ref — Inner::Deep is compact
        expect(groups).to include(["Outer::Inner::Deep::Ref", "Outer::Ref", "Ref"])
      end
    end

    it "returns empty array for files with syntax errors" do
      with_tempfile("def foo(\n") do |path|
        expect(described_class.extract(path)).to eq([])
      end
    end

    it "returns empty array for files with no constant references" do
      with_tempfile("x = 1 + 2\n") do |path|
        expect(described_class.extract(path)).to eq([])
      end
    end

    it "extracts superclass references" do
      with_tempfile("class Foo < Bar; end\n") do |path|
        groups = described_class.extract(path)

        expect(groups).to include(["Bar"])
      end
    end

    def with_tempfile(content)
      file = Tempfile.new(["extractor_test", ".rb"])
      file.write(content)
      file.close
      yield file.path
    ensure
      file.unlink
    end
  end
end
