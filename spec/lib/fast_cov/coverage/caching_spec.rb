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

    expect(warm_result.to_a.sort).to eq(cold_result.to_a.sort)
  end

  it "resolves constants correctly even after cache is cleared between runs" do
    subject.start
    ConstantReader.new.operations
    first_result = subject.stop

    FastCov::Cache.clear

    subject.start
    ConstantReader.new.operations
    second_result = subject.stop

    expect(second_result).to include(
      fixtures_path("calculator/operations/constant_reader.rb"),
      fixtures_path("calculator/constants.rb")
    )
    expect(second_result.to_a.sort).to eq(first_result.to_a.sort)
  end

  it "reuses cached source_file -> resolved_files outcomes on warm runs" do
    coverage = described_class.new(root: root, allocations: false)
    reader_file = fixtures_path("calculator/operations/constant_reader.rb")
    constants_file = fixtures_path("calculator/constants.rb")

    coverage.start
    ConstantReader.new.operations
    coverage.stop

    expect(FastCov::Cache.data[:const_ref_files][reader_file]).to include(constants_file)

    FastCov::Cache.data[:const_locations].clear
    expect(Object).not_to receive(:const_source_location)

    coverage.start
    ConstantReader.new.operations
    warm_result = coverage.stop

    expect(warm_result).to include(reader_file, constants_file)
  end

  it "stores cached constant resolution paths as frozen shared strings" do
    coverage = described_class.new(root: root, allocations: false)
    coverage.start
    ConstantReader.new.operations
    coverage.stop

    const_location_paths = FastCov::Cache.data[:const_locations].values
    const_ref_file_paths = FastCov::Cache.data[:const_ref_files].values.flatten
    cached_paths = const_location_paths + const_ref_file_paths

    expect(cached_paths).not_to be_empty
    expect(cached_paths).to all(be_a(String))
    expect(cached_paths).to all(be_frozen)
  end
end
