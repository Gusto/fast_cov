# frozen_string_literal: true

RSpec.describe FastCov::ConnectedDependencies do
  subject(:connected_dependencies) { described_class.new }

  describe "#connect" do
    it "stores connections" do
      connected_dependencies.connect(from: "/app/services/config_reader.rb", to: "/app/config/settings.yml")

      expanded_paths = connected_dependencies.expand(Set["/app/services/config_reader.rb"])

      expect(expanded_paths).to include("/app/config/settings.yml")
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
