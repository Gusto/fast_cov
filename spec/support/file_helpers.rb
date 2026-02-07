# frozen_string_literal: true

module FileHelpers
  FIXTURES_ROOT = File.expand_path("../fixtures", __dir__)

  def fixtures_path(*segments)
    File.join(FIXTURES_ROOT, *segments)
  end
end
