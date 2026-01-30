require_relative "../../../lib/models/pipeline_group"
require_relative "../../../lib/models/pipeline_summary"

class StubSummary
  attr_accessor :status
end

describe PipelineGroup do
  subject(:pipeline_group) do
    described_class.new("test", [pipeline_a, pipeline_b, pipeline_c])
  end

  let(:pipeline_a) { StubSummary.new }
  let(:pipeline_b) { StubSummary.new }
  let(:pipeline_c) { StubSummary.new }

  describe "state shows the worst state in the group and" do
    # %w[]
    # %w[Cancelled Failed]
    it "Succeeded is the best state" do
      pipeline_a.status = "Succeeded"
      pipeline_b.status = "Succeeded"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "Succeeded"
    end

    it "InProgress is worse than Succeeded" do
      pipeline_a.status = "Succeeded"
      pipeline_b.status = "InProgress"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "InProgress"
    end

    it "Superseded is worse than Succeeded" do
      pipeline_a.status = "Succeeded"
      pipeline_b.status = "Superseded"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "Superseded"
    end

    it "Stopped is worse than Superseded" do
      pipeline_a.status = "Superseded"
      pipeline_b.status = "Stopped"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "Stopped"
    end

    it "Stopping is worse than Stopped" do
      pipeline_a.status = "Stopped"
      pipeline_b.status = "Stopping"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "Stopping"
    end

    it "Cancelled is worse than Stopping" do
      pipeline_a.status = "Stopping"
      pipeline_b.status = "Cancelled"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "Cancelled"
    end

    it "Failed is the worst status" do
      pipeline_a.status = "Cancelled"
      pipeline_b.status = "Failed"
      pipeline_c.status = "Succeeded"

      expect(pipeline_group.status).to eq "Failed"
    end
  end
end
