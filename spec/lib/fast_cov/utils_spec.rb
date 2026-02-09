# frozen_string_literal: true

RSpec.describe FastCov::Utils do
  describe ".path_within?" do
    it "returns true when path is within root" do
      expect(described_class.path_within?("/a/b/c/foo.rb", "/a/b/c")).to be true
    end

    it "returns true when path is exactly root" do
      expect(described_class.path_within?("/a/b/c", "/a/b/c")).to be true
    end

    it "returns false for sibling directory with longer name" do
      # /a/b/cd is NOT within /a/b/c - it's a sibling directory
      expect(described_class.path_within?("/a/b/cd/foo.rb", "/a/b/c")).to be false
    end

    it "handles root with trailing slash" do
      expect(described_class.path_within?("/a/b/c/foo.rb", "/a/b/c/")).to be true
    end

    it "handles sibling directory when root has trailing slash" do
      expect(described_class.path_within?("/a/b/cd/foo.rb", "/a/b/c/")).to be false
    end

    it "returns false when path is completely different" do
      expect(described_class.path_within?("/other/path.rb", "/a/b/c")).to be false
    end

    it "returns false when path is shorter than root" do
      expect(described_class.path_within?("/a/b", "/a/b/c")).to be false
    end

    it "returns true for deeply nested paths" do
      expect(described_class.path_within?("/a/b/c/d/e/f/g.rb", "/a/b/c")).to be true
    end
  end

  describe ".relativize_paths" do
    it "converts absolute paths to relative paths" do
      hash = {"/app/models/user.rb" => true, "/app/models/post.rb" => true}
      result = described_class.relativize_paths(hash, "/app")

      expect(result.keys).to contain_exactly("models/user.rb", "models/post.rb")
    end

    it "leaves paths outside root unchanged" do
      hash = {"/app/models/user.rb" => true, "/other/file.rb" => true}
      result = described_class.relativize_paths(hash, "/app")

      expect(result.keys).to contain_exactly("models/user.rb", "/other/file.rb")
    end

    it "handles root with trailing slash" do
      hash = {"/app/models/user.rb" => true}
      result = described_class.relativize_paths(hash, "/app/")

      expect(result.keys).to contain_exactly("models/user.rb")
    end

    it "does not match sibling directories with longer names" do
      hash = {"/app/models/user.rb" => true, "/application/config.rb" => true}
      result = described_class.relativize_paths(hash, "/app")

      # /application should NOT be relativized because it's not within /app
      expect(result.keys).to contain_exactly("models/user.rb", "/application/config.rb")
    end

    it "preserves hash values" do
      hash = {"/app/a.rb" => {lines: [1, 2]}, "/app/b.rb" => {lines: [3, 4]}}
      result = described_class.relativize_paths(hash, "/app")

      expect(result["a.rb"]).to eq({lines: [1, 2]})
      expect(result["b.rb"]).to eq({lines: [3, 4]})
    end

    it "returns the modified hash" do
      hash = {"/app/file.rb" => true}
      result = described_class.relativize_paths(hash, "/app")

      expect(result).to be(hash)
    end
  end
end
