# frozen_string_literal: true

RSpec.shared_context "coverage instance" do
  let(:ignored_path) { nil }
  let(:threading_mode) { :multi }
  let(:use_allocation_tracing) { true }

  subject do
    described_class.new(
      root: root,
      ignored_path: ignored_path,
      threading_mode: threading_mode,
      use_allocation_tracing: use_allocation_tracing
    )
  end

  let!(:calculator) { Calculator.new }
end
