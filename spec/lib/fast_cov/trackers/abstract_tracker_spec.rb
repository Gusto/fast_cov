# frozen_string_literal: true

RSpec.describe FastCov::AbstractTracker do
  let(:config) do
    double("config",
      root: "/app",
      ignored_path: "/app/vendor",
      threads: true
    )
  end

  subject(:tracker) { described_class.new(config) }

  before do
    described_class.reset
  end

  describe "#initialize" do
    it "reads root from config" do
      expect(tracker.instance_variable_get(:@root)).to eq("/app")
    end

    it "reads ignored_path from config" do
      expect(tracker.instance_variable_get(:@ignored_path)).to eq("/app/vendor")
    end

    it "reads threads from config" do
      expect(tracker.instance_variable_get(:@threads)).to eq(true)
    end

    it "allows options to override config" do
      tracker = described_class.new(config, root: "/other", ignored_path: nil, threads: false)
      expect(tracker.instance_variable_get(:@root)).to eq("/other")
      expect(tracker.instance_variable_get(:@ignored_path)).to be_nil
      expect(tracker.instance_variable_get(:@threads)).to eq(false)
    end
  end

  describe "#start" do
    it "initializes @files as empty Set" do
      tracker.start
      expect(tracker.instance_variable_get(:@files)).to eq(Set.new)
    end

    it "sets self.class.active to self" do
      tracker.start
      expect(described_class.active).to eq(tracker)
    end

    it "calls on_start hook" do
      called = false
      tracker.define_singleton_method(:on_start) { called = true }
      tracker.start
      expect(called).to be true
    end

    context "with threads: false" do
      let(:config) { double("config", root: "/app", ignored_path: nil, threads: false) }

      it "stores the starting thread" do
        tracker.start
        expect(tracker.instance_variable_get(:@started_thread)).to eq(Thread.current)
      end
    end

    context "with threads: true" do
      it "does not store the starting thread" do
        tracker.start
        expect(tracker.instance_variable_get(:@started_thread)).to be_nil
      end
    end
  end

  describe "#stop" do
    before { tracker.start }

    it "returns the recorded files" do
      tracker.record("/app/foo.rb")
      result = tracker.stop
      expect(result).to eq(Set["/app/foo.rb"])
    end

    it "clears self.class.active" do
      tracker.stop
      expect(described_class.active).to be_nil
    end

    it "resets @files to nil" do
      tracker.stop
      expect(tracker.instance_variable_get(:@files)).to be_nil
    end

    it "calls on_stop hook" do
      called = false
      tracker.define_singleton_method(:on_stop) { called = true }
      tracker.stop
      expect(called).to be true
    end
  end

  describe "#record" do
    before { tracker.start }

    it "records files within root" do
      tracker.record("/app/models/user.rb")
      expect(tracker.instance_variable_get(:@files)).to include("/app/models/user.rb")
    end

    it "ignores files outside root" do
      tracker.record("/other/file.rb")
      expect(tracker.instance_variable_get(:@files)).to be_empty
    end

    it "ignores files within ignored_path" do
      tracker.record("/app/vendor/gem.rb")
      expect(tracker.instance_variable_get(:@files)).to be_empty
    end

    it "calls on_record hook and respects its return value" do
      tracker.define_singleton_method(:on_record) { |path| path.end_with?(".rb") }

      tracker.record("/app/foo.rb")
      tracker.record("/app/bar.txt")

      files = tracker.instance_variable_get(:@files)
      expect(files).to include("/app/foo.rb")
      expect(files).not_to include("/app/bar.txt")
    end

    context "with threads: false" do
      let(:config) { double("config", root: "/app", ignored_path: nil, threads: false) }

      it "records from the starting thread" do
        tracker.start
        tracker.record("/app/foo.rb")
        expect(tracker.instance_variable_get(:@files)).to include("/app/foo.rb")
      end

      it "ignores records from other threads" do
        tracker.start
        thread = Thread.new { tracker.record("/app/foo.rb") }
        thread.join
        expect(tracker.instance_variable_get(:@files)).to be_empty
      end
    end

    context "with threads: true" do
      it "records from any thread" do
        thread = Thread.new { tracker.record("/app/foo.rb") }
        thread.join
        expect(tracker.instance_variable_get(:@files)).to include("/app/foo.rb")
      end
    end
  end

  describe "#install" do
    it "is a no-op by default" do
      expect { tracker.install }.not_to raise_error
    end
  end

  describe "#on_record" do
    it "returns true by default" do
      expect(tracker.on_record("/any/path.rb")).to be true
    end
  end

  describe ".reset" do
    it "clears active" do
      tracker.start
      described_class.reset
      expect(described_class.active).to be_nil
    end
  end

  describe ".record (class method)" do
    it "delegates to active instance when active" do
      tracker.start
      described_class.record("/app/foo.rb")
      expect(tracker.instance_variable_get(:@files)).to include("/app/foo.rb")
    end

    it "safely no-ops when no active instance" do
      expect { described_class.record("/app/foo.rb") }.not_to raise_error
    end

    context "with block form" do
      it "yields block and records result when active" do
        tracker.start
        described_class.record { "/app/foo.rb" }
        expect(tracker.instance_variable_get(:@files)).to include("/app/foo.rb")
      end

      it "does not yield block when inactive" do
        yielded = false
        described_class.record { yielded = true; "/app/foo.rb" }
        expect(yielded).to be false
      end

      it "ignores nil block results" do
        tracker.start
        described_class.record { nil }
        expect(tracker.instance_variable_get(:@files)).to be_empty
      end

      it "prefers direct value over block" do
        tracker.start
        described_class.record("/app/direct.rb") { "/app/block.rb" }
        files = tracker.instance_variable_get(:@files)
        expect(files).to include("/app/direct.rb")
        expect(files).not_to include("/app/block.rb")
      end
    end
  end

  describe "subclass isolation" do
    let(:subclass_a) { Class.new(described_class) }
    let(:subclass_b) { Class.new(described_class) }

    it "each subclass has its own active tracker" do
      tracker_a = subclass_a.new(config)
      tracker_b = subclass_b.new(config)

      tracker_a.start
      tracker_b.start

      expect(subclass_a.active).to eq(tracker_a)
      expect(subclass_b.active).to eq(tracker_b)
    end
  end
end
