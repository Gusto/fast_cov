# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "robustness" do
  include_context "coverage instance"
  let(:root) { fixtures_path("app") }

  it "survives GC stress during allocation tracing" do
    subject.start

    10_000.times do |i|
      MyModel.new
      GC.start(full_mark: true, immediate_sweep: true) if i % 100 == 0
    end

    coverage = subject.stop
    expect(coverage.keys).to include(
      fixtures_path("app/model/my_model.rb"),
      fixtures_path("app/model/my_parent_model.rb"),
      fixtures_path("app/model/my_grandparent_model.rb"),
      fixtures_path("app/concerns/queryable.rb")
    )
  end

  it "handles BasicObject subclasses without crashing" do
    klass = Class.new(BasicObject) do
      def initialize
      end
    end

    subject.start

    klass.new
    MyModel.new

    coverage = subject.stop
    expect(coverage.keys).to include(fixtures_path("app/model/my_model.rb"))
  end

  it "handles anonymous classes without crashing" do
    subject.start

    MyModel.new
    c = Class.new(Object) {}
    c.new

    # Trigger a NameError internally to exercise the C extension's
    # safe constant resolution path — we just need it not to segfault.
    Object.const_get(:fdsfdsfdsfds) rescue nil # rubocop:disable Style/RescueModifier

    coverage = subject.stop
    expect(coverage.size).to eq(4)
    expect(coverage.keys).to include(
      fixtures_path("app/model/my_model.rb"),
      fixtures_path("app/model/my_parent_model.rb"),
      fixtures_path("app/model/my_grandparent_model.rb"),
      fixtures_path("app/concerns/queryable.rb")
    )
  end

  it "handles many rapid start/stop cycles" do
    100.times do
      subject.start
      MyModel.new
      coverage = subject.stop
      expect(coverage.keys).to include(fixtures_path("app/model/my_model.rb"))
    end
  end
end
