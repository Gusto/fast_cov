# frozen_string_literal: true

RSpec.describe FastCov::Coverage, "allocation tracing" do
  include_context "coverage instance"
  let(:root) { fixtures_path("app") }

  context "when enabled" do
    let(:allocation_tracing) { true }

    it "tracks coverage for a model and its full ancestor chain" do
      subject.start
      MyModel.new
      coverage = subject.stop

      expect(coverage.size).to eq(4)
      expect(coverage.keys).to include(
        fixtures_path("app/model/my_model.rb"),
        fixtures_path("app/model/my_parent_model.rb"),
        fixtures_path("app/model/my_grandparent_model.rb"),
        fixtures_path("app/concerns/queryable.rb")
      )
    end

    it "does not re-report classes on a subsequent run" do
      subject.start
      MyModel.new
      subject.stop

      # second run with no new allocations
      MyModel.new
      subject.start
      coverage = subject.stop
      expect(coverage.size).to eq(0)
    end

    it "tracks coverage for Struct subclasses" do
      subject.start
      User.new("john doe", "johndoe@mail.test")
      coverage = subject.stop

      expect(coverage.size).to eq(1)
      expect(coverage.keys).to include(fixtures_path("app/model/my_struct.rb"))
    end

    context "Data structs (Ruby >= 3.2)" do
      before do
        require_relative "../../../fixtures/app/model/measure"
      end

      it "tracks coverage for Data subclasses" do
        subject.start
        Measure.new(100, "km")
        coverage = subject.stop

        expect(coverage.size).to eq(1)
        expect(coverage.keys).to include(fixtures_path("app/model/measure.rb"))
      end
    end

    it "tracks coverage for classes that use method_missing" do
      subject.start
      model = DynamicModel.new
      result = model.any_method_name(1, 2, 3)
      coverage = subject.stop

      expect(result).to eq("called any_method_name with [1, 2, 3]")
      expect(coverage.keys).to include(fixtures_path("app/model/dynamic_model.rb"))
    end

    context "when Object.const_source_location is stubbed" do
      shared_examples "does not break" do
        it "returns empty coverage" do
          subject.start
          User.new("john doe", "johndoe@mail.test")
          coverage = subject.stop
          expect(coverage.size).to eq(0)
        end
      end

      context "returning invalid values" do
        before { allow(Object).to receive(:const_source_location).and_return([-1, -1]) }
        include_examples "does not break"
      end

      context "returning nil" do
        before { allow(Object).to receive(:const_source_location).and_return(nil) }
        include_examples "does not break"
      end

      context "returning empty array" do
        before { allow(Object).to receive(:const_source_location).and_return([]) }
        include_examples "does not break"
      end

      context "returning empty nested array" do
        before { allow(Object).to receive(:const_source_location).and_return([[]]) }
        include_examples "does not break"
      end

      context "raising an exception" do
        before { allow(Object).to receive(:const_source_location).and_raise(StandardError) }
        include_examples "does not break"
      end
    end
  end

  context "when disabled" do
    let(:allocation_tracing) { false }

    it "does not track coverage for object allocations" do
      subject.start

      MyModel.new
      expect(calculator.add(1, 2)).to eq(3)

      coverage = subject.stop
      expect(coverage.size).to eq(0)
    end
  end
end
