# frozen_string_literal: true

module FastCov
  module Utils
    # Check if path is within directory, correctly handling:
    # - Trailing slashes on directory
    # - Sibling directories with longer names (e.g., /a/b/c vs /a/b/cd)
    def self.path_within?(path, directory)
      dir = directory.end_with?("/") ? directory.chop : directory
      return true if path == dir

      path.start_with?("#{dir}/")
    end

    # Mutates set in place: converts absolute paths to relative paths from root.
    # Paths not within root are left unchanged.
    def self.relativize_paths(set, root)
      prefix = root.end_with?("/") ? root : "#{root}/"

      set.to_a.each do |abs_path|
        next unless abs_path.is_a?(String)
        next unless abs_path.start_with?(prefix) || abs_path == root.chomp("/")

        set.delete(abs_path)
        set.add(abs_path.delete_prefix(prefix))
      end

      set
    end

    # Walk caller locations to find the first frame whose file is within root.
    # Handles indirect calls (e.g., YAML.load_file -> File.open) where the
    # immediate caller is a stdlib/gem file outside the project.
    def self.resolve_caller(locations, root)
      locations.each do |loc|
        path = loc.absolute_path
        next unless path

        return path if path_within?(path, root)
      end
      nil
    end
  end
end
