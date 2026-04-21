require "aws-sdk-codepipeline"

class LiveAWSSDKFactory
  # @return [Aws::CodePipeline::Client]
  # @param [string] role_arn - ARN of role to assume (optional)
  def self.new_code_pipeline(role_arn = nil)
    if role_arn
      Aws::CodePipeline::Client.new(
        credentials: Aws::AssumeRoleCredentials.new(
          role_arn: role_arn,
          role_session_name: "pipeline-visualiser-session",
          region: "eu-west-2"
        ),
        region: "eu-west-2"
      )
    else
      # Use default credentials (ECS task role)
      Aws::CodePipeline::Client.new(region: "eu-west-2")
    end
  end
end
