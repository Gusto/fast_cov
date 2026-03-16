# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "initialization" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator") }

  it "raises RuntimeError when started without a root" do
    cov = described_class.allocate
    expect { cov.start }.to raise_error(RuntimeError, "root is required")
  end

  it "raises TypeError when root is not a String" do
    expect do
      described_class.new(root: 123)
    end.to raise_error(TypeError)
  end

  it "raises TypeError when ignored_paths is not an Array" do
    expect do
      described_class.new(root: root, ignored_paths: "vendor")
    end.to raise_error(TypeError)
  end

  it "raises TypeError when ignored_paths contains a non-String value" do
    expect do
      described_class.new(root: root, ignored_paths: [123])
    end.to raise_error(TypeError)
  end
end
