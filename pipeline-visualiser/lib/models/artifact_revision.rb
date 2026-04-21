class ArtifactRevision
  attr_accessor :name, :revision_id, :revision_summary

  # @param [Aws::CodePipeline::Types::ArtifactRevision] artifact
  def initialize(artifact)
    @name = artifact.name
    @revision_id = artifact.revision_id
    if artifact.revision_summary.nil?
      @revision_summary = "No summary available"
    elsif artifact.revision_summary.start_with? "{"
      summary_json = JSON.parse(artifact.revision_summary)
      @revision_summary = case summary_json["ProviderType"]
                          when "GitHub", "CodeCommit"
                            summary_json["CommitMessage"]
                          else
                            "Error: Unknown provider type"
                          end
    else
      @revision_summary = artifact.revision_summary
    end
  end
end
