# frozen_string_literal: true

RSpec.describe FastCov::Configuration do
  it "yields the configuration via configure block" do
    FastCov.configure do |config|
      expect(config).to be_a(FastCov::Configuration)
      config.use FastCov::CoverageTracker
    end
  end

  it "registers trackers via use" do
    expect(FastCov.configured?).to be false
    FastCov.configure do |c|
      c.root = Dir.pwd
      c.use FastCov::CoverageTracker
    end
    expect(FastCov.configured?).to be true
  end
end
