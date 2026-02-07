# frozen_string_literal: true

RSpec.describe FastCov::Configuration do
  after { FastCov.configuration.reset }

  it "returns the same configuration instance across calls" do
    expect(FastCov.configuration).to be(FastCov.configuration)
  end

  it "yields the configuration via configure block" do
    FastCov.configure do |config|
      expect(config).to be(FastCov.configuration)
    end
  end

  it "restores defaults on reset" do
    FastCov.configuration.reset
    expect(FastCov.configuration).to be_a(FastCov::Configuration)
  end
end
