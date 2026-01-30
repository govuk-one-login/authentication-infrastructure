require_relative "../../../lib/models/pipeline_stage"
require "aws-sdk-codepipeline"
require "aws-sdk-codepipeline/types"

describe PipelineStage do
  subject(:pipeline_stage) do
    described_class.new(codepipeline_stage, "execution-1")
  end

  let(:codepipeline_stage) do
    Aws::CodePipeline::Types::StageState.new(
      stage_name: "stage_name",
      latest_execution: Aws::CodePipeline::Types::StageExecution.new(
        pipeline_execution_id: "execution-2",
        status: "Failed",
      ),
      inbound_transition_state: Aws::CodePipeline::Types::TransitionState.new(
        enabled: false,
        disabled_reason: "Paused",
        last_changed_at: Time.now - (1 * 60 * 60), # 1 hour ago
      ),
      action_states: [
        Aws::CodePipeline::Types::ActionState.new(
          action_name: "action-1",
          latest_execution: Aws::CodePipeline::Types::ActionExecution.new(
            status: "Succeeded",
          ),
        ),
        Aws::CodePipeline::Types::ActionState.new(
          action_name: "action-2",
          latest_execution: Aws::CodePipeline::Types::ActionExecution.new(
            status: "Failed",
            summary: "action error message",
          ),
        ),
      ],
    )
  end

  it "name comes from the name of the CodePipeline stage stage_name" do
    expect(pipeline_stage.name).to eq "stage_name"
  end

  it "status comes from the latest execution status" do
    expect(pipeline_stage.status).to eq "Failed"
  end

  it "is outdated if the current execution id is not the same as the latest" do
    expect(pipeline_stage.outdated).to be true
  end

  it "is not outdated if the current execution id matches the latest execution id" do
    pipeline_stage = described_class.new(codepipeline_stage, "execution-2")
    expect(pipeline_stage.outdated).to be false
  end

  it "is paused when the inbound transition state is disabled" do
    expect(pipeline_stage.paused).to be true
  end

  it "is not paused when the inbound transition state is enabled" do
    codepipeline_stage.inbound_transition_state.enabled = true
    expect(pipeline_stage.paused).to be false
  end

  describe "when stage state not Failed" do
    it "error message is nil" do
      codepipeline_stage.latest_execution.status = "Succeeded"
      pipeline_stage = described_class.new(codepipeline_stage, "execution-1")

      expect(pipeline_stage.error_message).to be_nil
    end
  end

  describe "when stage state is Failed" do
    it "error message comes from the first failed action" do
      expect(pipeline_stage.error_message).to eq "action error message"
    end
  end
end
