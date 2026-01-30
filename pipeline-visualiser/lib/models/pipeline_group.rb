class PipelineGroup
  # @attribute [PipelineSummary[]]
  attr_reader :summaries
  attr_reader :name

  # @param [PipelineSummary[]] pipeline_summaries
  def initialize(name, pipeline_summaries)
    @name = name
    @summaries = pipeline_summaries

    # Used to find the worst status in the group
    # A lower number is a worse status
    @status_values = {
      "Succeeded" => 7,
      "InProgress" => 6,
      "Superseded" => 5,
      "Stopped" => 4,
      "Stopping" => 3,
      "Cancelled" => 2,
      "Failed" => 1,
    }
  end

  def status
    return "Unknown" if @summaries.empty?

    sorted_summaries = @summaries.sort_by do |summary|
      @status_values[summary.status]
    end

    sorted_summaries[0].status
  end

  def pipelines
    @summaries
  end
end
