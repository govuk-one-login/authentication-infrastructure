# authentication-infrastructure

## Bootstrapping an account

Configure AWS SSO as described in [Setting Up SSO Profiles (Confluence)](https://govukverify.atlassian.net/wiki/spaces/LO/pages/3831890210/How+to+deploy+to+sandpit+authdev+environments#Setting-up-SSO-profiles)

Run `./provision-<environment>.sh` to bootstrap an account. You may be prompted to authenticate with AWS Identity Center before continuing.

Run `./provision-cloudfront.sh <environment>` to deploy CloudFront distribution and additional dependencies described in the [CloudFront header](https://govukverify.atlassian.net/wiki/spaces/DID/pages/4026401532/Part+1+-+Deploying+CloudFront) trust initiative.

### Helper scripts

[sync-dependencies.sh](./sync-dependencies.sh) - deploys and maintains a shallow copy of authentication-frontend repository, in order to source several cloudformation templates used in the provision scripts

[read_secrets.sh](./scripts/read_secrets.sh) - extracts all secrets stored in AWS Secrets Manager named as `/deploy/\${Environment}/secret-name` and export to shell as `secret-name=value`

[read_parameters.sh](./scripts/read_parameters.sh) - extracts all parameters stored in AWS Systems Manager Parameter store named as `/deploy/\${Environment}/param-name` and export to shell as `param-name=value`

Both secrets and parameters are then injected to the provisioner script

[read_cloudformation_stack_outputs.sh](./scripts/read_cloudformation_stack_outputs.sh) - takes a CloudFormation stack name as input, and exports the outputs from that CloudFormation stack into shell in the `CFN_<stackname>_OutputKey=OutputValue` format. Any hyphens "-" in the stack name are converted to underscores "_"
