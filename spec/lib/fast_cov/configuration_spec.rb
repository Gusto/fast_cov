# frozen_string_literal: true

RSpec.describe FastCov::Configuration do
  after { FastCov.configuration.reset }

  it "defaults cache_path to tmp/cache/fast_cov" do
    expect(FastCov.configuration.cache_path).to eq("tmp/cache/fast_cov")
  end

  it "allows overriding cache_path via configure block" do
    FastCov.configure { |c| c.cache_path = "/custom/path" }
    expect(FastCov.configuration.cache_path).to eq("/custom/path")
  end

  it "returns the same configuration instance across calls" do
    expect(FastCov.configuration).to be(FastCov.configuration)
  end

  it "returns a fresh instance after reset" do
    FastCov.configure { |c| c.cache_path = "/changed" }
    FastCov.configuration.reset
    expect(FastCov.configuration.cache_path).to eq("tmp/cache/fast_cov")
  end
end
