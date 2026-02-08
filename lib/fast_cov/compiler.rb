# frozen_string_literal: true

require "fileutils"
require "rbconfig"

module FastCov
  module Compiler
    EXT_DIR = File.expand_path("../../ext/fast_cov", __dir__)
    LIB_DIR = File.expand_path("../fast_cov", __dir__)

    def self.compile!
      Dir.chdir(EXT_DIR) do
        system(RbConfig.ruby, "extconf.rb") || raise("FastCov: extconf.rb failed")
        system("make") || raise("FastCov: make failed")
        system("make install sitearchdir=#{LIB_DIR} sitelibdir=#{LIB_DIR}") || raise("FastCov: make install failed")
      end
    end
  end
end
