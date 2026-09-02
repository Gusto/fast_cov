# frozen_string_literal: true

if RUBY_ENGINE != "ruby" || Gem.win_platform?
  warn("WARN: Skipping build of fast_cov native extension (unsupported platform).")
  File.write("Makefile", "all install clean: # dummy makefile\n")
  exit
end

require "mkmf"

# Tagged with the ABI version so multiple Ruby versions can coexist in
# development. Must stay in sync with the require in lib/fast_cov.rb.
create_makefile("fast_cov/fast_cov.#{RbConfig::CONFIG["ruby_version"]}")
