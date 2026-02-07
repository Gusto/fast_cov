# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "caching" do
  include_context "coverage instance"
  let(:root) { fixtures_path("calculator") }

  it "produces identical results on a warm cache as on a cold cache" do
    subject.start
    ConstantReader.new.operations
    cold_result = subject.stop

    subject.start
    ConstantReader.new.operations
    warm_result = subject.stop

    expect(warm_result.keys.sort).to eq(cold_result.keys.sort)
  end

  it "resolves constants correctly even after cache is cleared between runs" do
    subject.start
    ConstantReader.new.operations
    first_result = subject.stop

    FastCov::Cache.clear

    subject.start
    ConstantReader.new.operations
    second_result = subject.stop

    expect(second_result.keys).to include(
      fixtures_path("calculator/operations/constant_reader.rb"),
      fixtures_path("calculator/constants.rb")
    )
    expect(second_result.keys.sort).to eq(first_result.keys.sort)
  end
end
