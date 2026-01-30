require "active_support"
require "active_support/duration"

class PipelineSummary
  attr_accessor :name, :execution_id, :last_started_at, :status, :gds_cli_role, :variables, :artifacts, :stages, :running_duration, :current_stage_name, :first_failing_stage_name, :first_failing_stage_error_message, :paused

  # @param [Aws::CodePipeline::Types::GetPipelineStateOutput] codepipeline_state
  # @param [Aws::CodePipeline::Types::PipelineExecutionSummary] codepipeline_execution
  # @param [Date] last_started_at
  def initialize(codepipeline_state, codepipeline_execution, last_started_at)
    @name = codepipeline_state.pipeline_name
    @execution_id = codepipeline_execution.pipeline_execution_id
    @last_started_at = last_started_at
    @status = codepipeline_execution.status
    @paused = codepipeline_state.stage_states.any? { |stage| !stage.inbound_transition_state.enabled }

    vars = codepipeline_execution.variables || []
    @variables = vars.map { |var| [var.name, var.resolved_value] }.to_h
    @artifacts = []
    @stages = []

    if !is_running?
      @running_duration = nil
    else
      now_seconds = Time.now.to_time.to_i
      last_start_seconds = @last_started_at.to_time.to_i
      @running_duration = ActiveSupport::Duration.build(now_seconds - last_start_seconds)

      codepipeline_state.stage_states.each do |stage|
        if stage.latest_execution.pipeline_execution_id == @execution_id && stage.latest_execution.status == "InProgress"
          @current_stage_name = stage.stage_name
          break
        end
      end
    end

    if @status == "Failed"
      failing_stage = codepipeline_state.stage_states.find { |stage| stage.latest_execution&.status == "Failed" }
      unless failing_stage.nil?
        @first_failing_stage_name = failing_stage.stage_name

        failing_action = failing_stage.action_states.find { |action| action.latest_execution&.status == "Failed" }
        unless failing_action.nil?
          if failing_action.latest_execution&.error_details&.message
            @first_failing_stage_error_message = failing_action.latest_execution.error_details.message
          elsif failing_action.latest_execution&.summary
            @first_failing_stage_error_message = failing_action.latest_execution.summary
          end
        end
      end
    end
  end

  def is_running?
    %w[InProgress Stopping].include? @status
  end

  def truncated_error_message(limit = 25)
    return nil if @first_failing_stage_error_message.nil?
    return @first_failing_stage_error_message if @first_failing_stage_error_message.length <= limit
    @first_failing_stage_error_message[0, limit] + "..."
  end

  def has_long_error_message?(limit = 25)
    return false if @first_failing_stage_error_message.nil?
    @first_failing_stage_error_message.length > limit
  end
end
