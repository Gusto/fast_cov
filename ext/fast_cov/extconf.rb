# frozen_string_literal: true

if RUBY_ENGINE != "ruby" || Gem.win_platform?
  warn("WARN: Skipping build of fast_cov native extension (unsupported platform).")
  File.write("Makefile", "all install clean: # dummy makefile\n")
  exit
end

require "mkmf"

create_makefile("fast_cov/fast_cov")
