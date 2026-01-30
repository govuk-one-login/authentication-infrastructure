require_relative "../../../lib/models/pipeline_summary"
require "aws-sdk-codepipeline"
require "aws-sdk-codepipeline/types"

describe PipelineSummary do
  subject(:pipeline_summary) do
    described_class.new(codepipeline_state, codepipeline_execution, last_start_at)
  end

  let(:codepipeline_state) do
    Aws::CodePipeline::Types::GetPipelineStateOutput.new(
      pipeline_name: "a_pipeline",
      created: Time.now,
      updated: Time.now,
      pipeline_version: 2,
      stage_states: [
        Aws::CodePipeline::Types::StageState.new(
          stage_name: "stage_1",
          latest_execution: Aws::CodePipeline::Types::StageExecution.new(
            pipeline_execution_id: "execution-1",
            status: "Succeeded",
          ),
          inbound_transition_state: Aws::CodePipeline::Types::TransitionState.new(
            enabled: true,
          ),
        ),
        Aws::CodePipeline::Types::StageState.new(
          stage_name: "stage_2",
          latest_execution: Aws::CodePipeline::Types::StageExecution.new(
            pipeline_execution_id: "execution-1",
            status: "InProgress",
          ),
          inbound_transition_state: Aws::CodePipeline::Types::TransitionState.new(
            enabled: true,
          ),
        ),
        Aws::CodePipeline::Types::StageState.new(
          stage_name: "stage_3",
          latest_execution: Aws::CodePipeline::Types::StageExecution.new(
            pipeline_execution_id: "execution-1",
            status: "Failed",
          ),
          inbound_transition_state: Aws::CodePipeline::Types::TransitionState.new(
            enabled: true,
          ),
          action_states: [
            Aws::CodePipeline::Types::ActionState.new(
              action_name: "action-1",
              latest_execution: Aws::CodePipeline::Types::ActionExecution.new(
                status: "Failed",
                summary: "AN ERROR MESSAGE",
              ),
            ),
          ],
        ),
      ],
    )
  end

  let(:codepipeline_execution) do
    Aws::CodePipeline::Types::PipelineExecution.new(
      pipeline_name: "a_pipeline",
      pipeline_version: 2,
      pipeline_execution_id: "execution-1",
      status: "Succeeded",
      variables: [
        Aws::CodePipeline::Types::ResolvedPipelineVariable.new(
          name: "Variable",
          resolved_value: "Some string value",
        ),
      ],
      artifact_revisions: [
        Aws::CodePipeline::Types::ArtifactRevision.new(
          name: "get-source",
          revision_id: "012abc",
          revision_summary: '{"ProviderType": "GitHub", "CommitMessage": "Some headline text\n\nFollowed by a bit more text which describes it in more detail"}',
        ),
      ],
    )
  end

  let(:last_start_at) do
    Date.parse("2024-04-01T00:00:00")
  end

  it "name comes from the name in the pipeline state" do
    expect(pipeline_summary.name).to eq "a_pipeline"
  end

  it "execution id comes from the id of the current execution" do
    expect(pipeline_summary.execution_id).to eq "execution-1"
  end

  it "last start time comes from the passed-in start time" do
    expect(pipeline_summary.last_started_at).to eq last_start_at
  end

  it "status comes from the status of the current execution" do
    expect(pipeline_summary.status).to eq "Succeeded"
  end

  it "artifacts is an empty array" do
    expect(pipeline_summary.artifacts).to eq []
  end

  it "stages is an empty array" do
    expect(pipeline_summary.stages).to eq []
  end

  describe "when there are no variables" do
    it "variables is an empty hash" do
      codepipeline_execution.variables = []
      pipeline_summary = described_class.new(codepipeline_state, codepipeline_execution, last_start_at)

      expect(pipeline_summary.variables).to eq({})
    end
  end

  describe "when there are variables" do
    it "converts them in to a hash" do
      expected_hash = {
        "Variable" => "Some string value",
      }
      expect(pipeline_summary.variables).to eq expected_hash
    end
  end

  describe "is_running" do
    %w[InProgress Stopping].each do |status|
      it "is true when the execution status is '#{status}'" do
        codepipeline_execution.status = status
        expect(pipeline_summary).to be_is_running
      end
    end

    %w[Cancelled Stopped Succeeded Superseded Failed].each do |status|
      it "is false when the execution status is '#{status}'" do
        codepipeline_execution.status = status
        expect(pipeline_summary).not_to be_is_running
      end
    end
  end

  context "when in a non-running state" do
    it "running_duration is nil" do
      codepipeline_execution.status = "Succeeded"
      expect(pipeline_summary.running_duration).to be_nil
    end

    it "current_stage_name is nil" do
      codepipeline_execution.status = "Succeeded"
      expect(pipeline_summary.current_stage_name).to be_nil
    end
  end

  context "when in a running state" do
    let(:last_start_at) do
      Time.now - (2 * 60 * 60) # 2 hours ago
    end

    before do
      codepipeline_execution.status = "InProgress"
    end

    it "running_duration is a duration between now and the last_started_at time" do
      duration = pipeline_summary.running_duration
      expect(duration.in_hours).to eq 2
    end

    it "current_stage_name is the name of the first stage in the current execution with the status 'InProgress'" do
      expect(pipeline_summary.current_stage_name).to eq "stage_2"
    end
  end

  context "when in a failing state" do
    before do
      codepipeline_execution.status = "Failed"
    end

    it "first_failing_stage_name is the name of the first stage with the Failed status" do
      expect(pipeline_summary.first_failing_stage_name).to eq "stage_3"
    end

    it "first_failing_stage_error_message is the error message coming from the first failing stage" do
      expect(pipeline_summary.first_failing_stage_error_message).to eq "AN ERROR MESSAGE"
    end
  end

  context "when one or more stages have disabled inbound transitions" do
    before do
      codepipeline_state.stage_states[1].inbound_transition_state = Aws::CodePipeline::Types::TransitionState.new(
        enabled: false,
        disabled_reason: "For testing purposes",
        last_changed_at: Time.now - (1 * 60 * 60), # 1 hour ago
      )
    end

    it "the pipeline summary shows paused" do
      expect(pipeline_summary.paused).to be true
    end
  end

  context "when no staged have disabled inbound transitions" do
    it "the pipeline summary shows as un-paused" do
      expect(pipeline_summary.paused).to be false
    end
  end
end
