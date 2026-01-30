class PipelineStage
  attr_accessor :name, :status, :outdated, :error_message, :paused

  # @param [Aws::CodePipeline::Types::StageState] codepipeline_stage
  # @param [string] current_execution_id
  def initialize(codepipeline_stage, current_execution_id)
    @name = codepipeline_stage.stage_name
    @status = codepipeline_stage.latest_execution.status
    @outdated = codepipeline_stage.latest_execution.pipeline_execution_id != current_execution_id
    @paused = !codepipeline_stage.inbound_transition_state.enabled

    if @status == "Failed"
      failing_action = codepipeline_stage.action_states.find do |action|
        action.latest_execution&.status == "Failed"
      end

      unless failing_action.nil?
        if failing_action.latest_execution&.error_details&.message
          @error_message = failing_action.latest_execution.error_details.message
        elsif failing_action.latest_execution&.summary
          @error_message = failing_action.latest_execution.summary
        end
      end
    end
  end
end
