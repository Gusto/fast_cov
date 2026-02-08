# frozen_string_literal: true

class ConfigReader
  def self.config_path
    File.expand_path("../config.yml", __dir__)
  end

  def self.read_config
    File.read(config_path)
  end
end
