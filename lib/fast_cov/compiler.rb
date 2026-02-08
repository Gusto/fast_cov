# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "digest/md5"

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

      write_digest
    end

    def self.stale?
      return true unless extension_exists?

      stored = read_digest
      return true unless stored

      stored != source_digest
    end

    def self.extension_exists?
      ext_name = "fast_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
      Dir.glob(File.join(LIB_DIR, "#{ext_name}.{bundle,so}")).any?
    end

    def self.source_digest
      files = Dir.glob(File.join(EXT_DIR, "*.{c,h,rb}")).sort
      combined = files.map { |f| Digest::MD5.file(f).hexdigest }.join
      Digest::MD5.hexdigest(combined)
    end

    def self.digest_path
      File.join(LIB_DIR, ".source_digest.#{RUBY_VERSION}_#{RUBY_PLATFORM}")
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
