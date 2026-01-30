require 'aws-sdk-codepipeline'

class SSOAWSSDKFactory
  # @return [Aws::CodePipeline::Client]
  # @param [string] profile_name
  def self.new_code_pipeline(config)
    Aws::CodePipeline::Client.new(
      credentials: Aws::SSOCredentials.new(
        sso_account_id: config['sso_account_id'].to_s,
        sso_role_name: config['sso_role_name'],
        sso_region: config['sso_region'],
        sso_session: config['sso_session']
      ),
      region: 'eu-west-2'
    )
  end
end
