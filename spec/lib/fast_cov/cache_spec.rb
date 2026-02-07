# frozen_string_literal: true

RSpec.describe FastCov::Cache do
  let(:cov) do
    FastCov::Coverage.new(
      root: fixtures_path("calculator"),
      threading_mode: :multi
    )
  end

  describe ".data" do
    it "returns the in-memory cache hash" do
      expect(FastCov::Cache.data).to be_a(Hash)
      expect(FastCov::Cache.data).to have_key("const_refs")
    end
  end

  describe ".data=" do
    it "raises TypeError for non-Hash input" do
      expect { FastCov::Cache.data = "bad" }.to raise_error(TypeError)
    end

    it "replaces the cache contents" do
      FastCov::Cache.data = { "const_refs" => { "/fake.rb" => { "digest" => "x", "refs" => ["Foo"] } } }
      expect(FastCov::Cache.data["const_refs"]).to have_key("/fake.rb")
    end
  end

  describe ".clear" do
    it "empties the cache" do
      cov.start
      ConstantReader.new.operations
      cov.stop

      expect(FastCov::Cache.data["const_refs"]).not_to be_empty

      FastCov::Cache.clear

      expect(FastCov::Cache.data["const_refs"]).to be_empty
    end
  end
end
