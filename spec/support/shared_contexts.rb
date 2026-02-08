# frozen_string_literal: true

RSpec.shared_context "coverage instance" do
  let(:ignored_path) { nil }

  subject do
    described_class.new(
      root: root,
      ignored_path: ignored_path
    )
  end

  let!(:calculator) { Calculator.new }
end
