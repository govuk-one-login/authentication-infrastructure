class AllPipelinesView
  attr_accessor :pipeline_groups

  def initialize(pipeline_groups)
    @pipeline_groups = pipeline_groups
  end

  def running_pipelines
    @pipeline_groups
      .collect(&:pipelines)
      .flatten
      .filter(&:is_running?)
  end

  def failing_pipelines
    @pipeline_groups
      .collect(&:pipelines)
      .flatten
      .filter { |pipeline| pipeline.status == "Failed" }
  end

  def pipeline_url(pipeline_name)
    group = @pipeline_groups.find do |grp|
      grp.pipelines.any? do |pipeline|
        pipeline.name == pipeline_name
      end
    end

    raise "pipeline '#{pipeline_name}' was not found in any group" if group.nil?

    group_slug = group.name.downcase.gsub(/[ _:\/]/, "-")
    pipeline_slug = pipeline_name.downcase.gsub(/[ _:\/]/, "-")

    "/group/#{group_slug}/pipeline/#{pipeline_slug}"
  end
end
