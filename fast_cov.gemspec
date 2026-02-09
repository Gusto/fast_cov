# frozen_string_literal: true

require_relative "lib/fast_cov/version"

Gem::Specification.new do |spec|
  spec.name = "fast_cov"
  spec.version = FastCov::VERSION
  spec.authors = ["Ngan Pham"]
  spec.homepage = "https://github.com/Gusto/fast_cov"
  spec.summary = "Fast native code coverage tracking for Ruby test impact analysis"
  spec.description = "A high-performance C extension that tracks which Ruby source files are executed during test runs, enabling test impact analysis."
  spec.license = "MIT"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/Gusto/fast_cov",
    "changelog_uri" => "https://github.com/Gusto/fast_cov/releases"
  }
  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir["lib/**/*.rb", "ext/**/*.{rb,c,h}", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/fast_cov/extconf.rb"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "factory_bot", "~> 6.0"
end
