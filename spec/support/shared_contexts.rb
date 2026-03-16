# frozen_string_literal: true

RSpec.shared_context "coverage instance" do
  let(:ignored_paths) { [] }

  subject do
    described_class.new(
      root: root,
      ignored_paths: ignored_paths
    )
  end

  let!(:calculator) { Calculator.new }
end
