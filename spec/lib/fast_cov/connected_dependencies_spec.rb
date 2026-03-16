# frozen_string_literal: true

RSpec.describe FastCov::ConnectedDependencies do
  let(:coverage_map) { instance_double(FastCov::CoverageMap) }

  subject(:connected_dependencies) { described_class.new(coverage_map) }

  before do
    allow(coverage_map).to receive(:include_path?) do |path|
      path.start_with?("/app") && !path.start_with?("/app/vendor")
    end
  end

  describe "#connect" do
    it "stores connections for valid paths" do
      connected_dependencies.connect(from: "/app/services/config_reader.rb", to: "/app/config/settings.yml")

      expanded_paths = connected_dependencies.expand(Set["/app/services/config_reader.rb"])

      expect(expanded_paths).to include("/app/config/settings.yml")
    end

    it "ignores invalid source paths" do
      connected_dependencies.connect(from: "/other/file.rb", to: "/app/config/settings.yml")

      expanded_paths = connected_dependencies.expand(Set["/other/file.rb"])

      expect(expanded_paths).not_to include("/app/config/settings.yml")
    end

    it "ignores self-referential connections" do
      connected_dependencies.connect(from: "/app/services/config_reader.rb", to: "/app/services/config_reader.rb")

      expanded_paths = connected_dependencies.expand(Set["/app/services/config_reader.rb"])

      expect(expanded_paths).to eq(Set["/app/services/config_reader.rb"])
    end
  end

  describe "#expand" do
    it "expands connections transitively" do
      connected_dependencies.connect(from: "/app/a.rb", to: "/app/b.rb")
      connected_dependencies.connect(from: "/app/b.rb", to: "/app/c.yml")

      paths = Set["/app/a.rb"]
      expanded_paths = connected_dependencies.expand(paths)

      expect(expanded_paths).to equal(paths)
      expect(expanded_paths).to include("/app/b.rb", "/app/c.yml")
    end

    it "raises unless paths is a Set" do
      expect { connected_dependencies.expand(["/app/a.rb"]) }
        .to raise_error(ArgumentError, "paths must be a Set")
    end
  end
end
