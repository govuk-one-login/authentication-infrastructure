require "aws-sdk-dynamodb"
require "json"

class PipelineHistoryStore
  TABLE_NAME = ENV["PIPELINE_HISTORY_TABLE"]

  def initialize
    @client = Aws::DynamoDB::Client.new(region: "eu-west-2") if TABLE_NAME
  end

  def save(pipeline_summary)
    return unless TABLE_NAME

    @client.put_item(
      table_name: TABLE_NAME,
      item: {
        "pipeline_name"   => pipeline_summary.name,
        "execution_id"    => pipeline_summary.execution_id,
        "started_at"      => pipeline_summary.last_started_at.utc.iso8601,
        "status"          => pipeline_summary.status,
        "stages"          => pipeline_summary.stages.map { |s| { "name" => s.name, "status" => s.status } },
        "artifacts"       => pipeline_summary.artifacts.map { |a| { "name" => a.name, "revision_id" => a.revision_id, "summary" => a.revision_summary } },
        "ttl"             => (Time.now + 90 * 24 * 60 * 60).to_i
      },
      condition_expression: "attribute_not_exists(execution_id)"
    )
  rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
    # already stored, skip
  rescue StandardError => e
    puts "Error saving pipeline history for #{pipeline_summary.name}: #{e.message}"
  end

  def fetch_history(pipeline_name, limit: 20)
    return [] unless TABLE_NAME

    result = @client.query(
      table_name: TABLE_NAME,
      key_condition_expression: "pipeline_name = :name",
      expression_attribute_values: { ":name" => pipeline_name },
      scan_index_forward: false,
      limit: limit
    )
    result.items
  rescue StandardError => e
    puts "Error fetching pipeline history for #{pipeline_name}: #{e.message}"
    []
  end
end
