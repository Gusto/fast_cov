# frozen_string_literal: true

if RUBY_ENGINE != "ruby" || Gem.win_platform?
  warn("WARN: Skipping build of fast_cov native extension (unsupported platform).")
  File.write("Makefile", "all install clean: # dummy makefile\n")
  exit
end

require "mkmf"

# Tag with Ruby version + platform so multiple versions coexist in lib/fast_cov/.
create_makefile("fast_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}")
