# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "initialization" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator") }

  it "raises RuntimeError when started without a root" do
    cov = described_class.allocate
    expect { cov.start }.to raise_error(RuntimeError, "root is required")
  end

  it "raises ArgumentError for an invalid threading mode" do
    expect {
      described_class.new(root: root, threading_mode: :invalid_mode)
    }.to raise_error(ArgumentError, "threading mode is invalid")
  end

  it "raises ArgumentError when allocation tracing is enabled in single threaded mode" do
    expect {
      described_class.new(
        root: root,
        threading_mode: :single,
        allocation_tracing: true
      )
    }.to raise_error(
      ArgumentError,
      "allocation tracing is not supported in single threaded mode"
    )
  end
end
