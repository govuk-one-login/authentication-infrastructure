require "concurrent/timer_task"
require "concurrent/map"

require_relative "lib/models/artifact_revision"
require_relative "lib/models/pipeline_group"
require_relative "lib/models/pipeline_stage"
require_relative "lib/models/pipeline_summary"

def start_background_pipeline_status_updater(aws_clients)
  pipelines_map = Concurrent::Map.new

  task = Concurrent::TimerTask.new(execution_interval: 30, run_now: true) do
    aws_clients.each do |client_config|
      client = client_config["client"]
      all_pipelines = client.list_pipelines
      pipeline_names = all_pipelines.pipelines.map(&:name)

      pipeline_names.each do |pipeline|
        state = client.get_pipeline_state({
          name: pipeline,
        })

        executions = client.list_pipeline_executions({
          pipeline_name: pipeline,
        })

        latest_execution_summary = executions.pipeline_execution_summaries
                                             .sort_by(&:start_time)
                                             .reverse
                                             .first

        latest_id = latest_execution_summary.pipeline_execution_id

        # To get variables we have to request the pipeline
        # execution with GetPipelineExecution
        latest = client.get_pipeline_execution({
          pipeline_name: pipeline,
          pipeline_execution_id: latest_id,
        })

        viewdata = generate_pipeline_viewdata(state, latest.pipeline_execution, latest_execution_summary.start_time, client_config["gds_cli_role"] || "")

        pipelines_map[viewdata.name] = viewdata
      rescue StandardError => e
        # Log only error message, not full backtrace
        puts "Error processing pipeline #{pipeline}: #{e.message}"
      end
    end
  end

  task.execute

  pipelines_map
end

def generate_pipeline_viewdata(state, execution, last_start_time, gds_cli_role)
  summary = PipelineSummary.new(state, execution, last_start_time)
  summary.gds_cli_role = gds_cli_role

  summary.artifacts = execution.artifact_revisions.map { |artifact| generate_artifact_viewdata(artifact) }
  summary.stages = state.stage_states.map { |stage| generate_stage_viewdata(stage, summary.execution_id) }

  summary
end

def generate_artifact_viewdata(artifact)
  ArtifactRevision.new(artifact)
end

def generate_stage_viewdata(stage, current_execution_id)
  PipelineStage.new(stage, current_execution_id)
end
