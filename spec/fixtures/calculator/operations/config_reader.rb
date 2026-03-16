# frozen_string_literal: true

class ConfigReader
  def self.config_path
    File.expand_path("../config.yml", __dir__)
  end

  def self.read_config
    File.read(config_path)
  end

  def self.memoized_config
    @memoized_config ||= read_config
  end

  def self.reset!
    remove_instance_variable(:@memoized_config) if instance_variable_defined?(:@memoized_config)
  end
end
