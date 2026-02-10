# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "digest/md5"

module FastCov
  module Compiler
    EXT_DIR = File.expand_path("../../ext/fast_cov", __dir__)
    LIB_DIR = File.expand_path("..", __dir__)     # lib/
    FAST_COV_DIR = File.expand_path(".", __dir__) # lib/fast_cov/

    def self.compile!
      clean_ext_dir!

      Dir.chdir(EXT_DIR) do
        system(RbConfig.ruby, "extconf.rb") || raise("FastCov: extconf.rb failed")
        system("make") || raise("FastCov: make failed")
        system("make install sitearchdir=#{LIB_DIR} sitelibdir=#{LIB_DIR}") || raise("FastCov: make install failed")
      end

      write_digest
    end

    def self.clean_ext_dir!
      # Clean stale build artifacts to prevent issues when switching Ruby versions
      FileUtils.rm_f(Dir.glob(File.join(EXT_DIR, "*.o")))
      FileUtils.rm_f(Dir.glob(File.join(EXT_DIR, "*.bundle")))
      FileUtils.rm_f(Dir.glob(File.join(EXT_DIR, "*.so")))
      FileUtils.rm_f(File.join(EXT_DIR, "Makefile"))
      FileUtils.rm_f(File.join(EXT_DIR, "mkmf.log"))
      FileUtils.rm_rf(Dir.glob(File.join(EXT_DIR, "*.dSYM")))
    end

    def self.stale?
      return true unless extension_exists?

      stored = read_digest
      return true unless stored

      stored != source_digest
    end

    def self.extension_exists?
      Dir.glob(File.join(FAST_COV_DIR, "fast_cov.#{RUBY_VERSION}.{bundle,so}")).any?
    end

    def self.source_digest
      files = Dir.glob(File.join(EXT_DIR, "*.{c,h,rb}")).sort
      combined = files.map { |f| Digest::MD5.file(f).hexdigest }.join
      Digest::MD5.hexdigest(combined)
    end

    def self.digest_path
      # Keep version-specific so we recompile when switching Ruby versions
      File.join(FAST_COV_DIR, ".source_digest.#{RUBY_VERSION}")
    end

    def self.write_digest
      File.write(digest_path, source_digest)
    end

    def self.read_digest
      File.read(digest_path).strip
    rescue Errno::ENOENT
      nil
    end
  end
end
