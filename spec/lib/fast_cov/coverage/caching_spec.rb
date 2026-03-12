# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "caching" do
  include_context "coverage instance"
  let(:root) { fixtures_path("app") }

  it "produces identical results on a warm cache as on a cold cache" do
    subject.start
    MyModel.new
    cold_result = subject.stop

    subject.start
    MyModel.new
    warm_result = subject.stop

    expect(warm_result.to_a.sort).to eq(cold_result.to_a.sort)
  end

  it "resolves allocation source locations correctly even after cache is cleared between runs" do
    subject.start
    MyModel.new
    first_result = subject.stop

    FastCov::Cache.clear

    subject.start
    MyModel.new
    second_result = subject.stop

    expect(second_result).to include(
      fixtures_path("app/model/my_model.rb"),
      fixtures_path("app/model/my_parent_model.rb"),
      fixtures_path("app/model/my_grandparent_model.rb"),
      fixtures_path("app/concerns/queryable.rb")
    )
    expect(second_result.to_a.sort).to eq(first_result.to_a.sort)
  end
end
