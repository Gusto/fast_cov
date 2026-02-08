# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "initialization" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator") }

  it "raises RuntimeError when started without a root" do
    cov = described_class.allocate
    expect { cov.start }.to raise_error(RuntimeError, "root is required")
  end
end
