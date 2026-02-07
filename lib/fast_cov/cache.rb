# frozen_string_literal: true

require "fileutils"

module FastCov
  # FastCov::Cache extends the C-defined module (which provides .data, .data=, .clear)
  # with disk persistence methods.
  module Cache
    CACHE_FILENAME = "fast_cov_cache.marshal"
    CACHE_VERSION = 1

    class << self
      # Wrap the C-defined clear to also reset Ruby state
      alias_method :_c_clear, :clear

      def clear
        _c_clear
        @loaded = false
      end

      def loaded?
        @loaded == true
      end

      def load(path = FastCov.configuration.cache_path)
        return false unless path

        file = cache_file_path(path)
        return false unless File.exist?(file)

        raw = File.binread(file)
        payload = Marshal.load(raw)

        if payload.is_a?(Hash) && payload["version"] == CACHE_VERSION
          self.data = payload["data"]
          @loaded = true
          true
        else
          false
        end
      rescue ArgumentError, TypeError, EOFError
        false
      end

      def save(path = FastCov.configuration.cache_path)
        return false unless path

        FileUtils.mkdir_p(path)

        payload = {
          "version" => CACHE_VERSION,
          "data" => data
        }

        file = cache_file_path(path)
        tmp = "#{file}.tmp.#{Process.pid}"
        File.binwrite(tmp, Marshal.dump(payload))
        File.rename(tmp, file)
        true
      rescue SystemCallError
        File.delete(tmp) if tmp && File.exist?(tmp)
        false
      end

      def setup_autosave
        at_exit { save }
      end

      private

      def cache_file_path(path)
        File.join(path, CACHE_FILENAME)
      end
    end
  end
end
