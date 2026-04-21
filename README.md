# authentication-infrastructure

## Bootstrapping an account

Configure AWS SSO as described in [Setting Up SSO Profiles (Confluence)](https://govukverify.atlassian.net/wiki/spaces/LO/pages/3831890210/How+to+deploy+to+sandpit+authdev+environments#Setting-up-SSO-profiles)

Run `./provision-<environment>.sh` to bootstrap an account. You may be prompted to authenticate with AWS Identity Center before continuing.

Run `./provision-cloudfront.sh <environment>` to deploy CloudFront distribution and additional dependencies described in the [CloudFront header](https://govukverify.atlassian.net/wiki/spaces/DID/pages/4026401532/Part+1+-+Deploying+CloudFront) trust initiative.

## Provision <env>

```bash
./provision-<env>.sh [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-b`, `--base-stacks` | Provision base stacks (api-gateway-logs, audit hooks, build-notifications, backup-monitoring) |
| `-n`, `--notification` | Creates a SNS topic with Slack integration and sets up a lambda code storage alarm |
| `-p`, `--pipelines` | Provision secure pipelines (frontend, authentication-api, account-management, orch-stub, smoke-test) |
| `-r`, `--pruner` | Provision Lambda version pruner |
| `-v`, `--vpc` | Provision VPC stack |
| `-l`, `--live-zone-resources <zone-only\|all>` | Provision live hosted zone, certificates and SSM params |
| `--pipeline-visualiser` | Deploy pipeline visualiser infrastructure (CodePipeline readonly role) |

Examples:

```bash
./provision-<env>.sh -b                        # Provision base stacks
./provision-<env>.sh -p                        # Provision pipelines
./provision-<env>.sh -l zone-only              # Provision hosted zone only
./provision-<env>.sh -l all                    # Provision hosted zone with all records
./provision-<env>.sh --pipeline-visualiser     # Deploy pipeline visualiser
./provision-<env>.sh -r                        # Provision Lambda version pruner
./provision-<env>.sh -b -v -p                  # Combine multiple options
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SKIP_AWS_AUTHENTICATION` | `true` | Skip AWS SSO authentication if already authenticated |
| `AUTO_APPLY_CHANGESET` | `false` | Automatically apply changesets without confirmation |

### Helper scripts

[sync-dependencies.sh](./sync-dependencies.sh) - deploys and maintains a shallow copy of authentication-frontend repository, in order to source several cloudformation templates used in the provision scripts

[read_secrets.sh](./scripts/read_secrets.sh) - extracts all secrets stored in AWS Secrets Manager named as `/deploy/\${Environment}/secret-name` and export to shell as `secret-name=value`

[read_parameters.sh](./scripts/read_parameters.sh) - extracts all parameters stored in AWS Systems Manager Parameter store named as `/deploy/\${Environment}/param-name` and export to shell as `param-name=value`

Both secrets and parameters are then injected to the provisioner script

[read_cloudformation_stack_outputs.sh](./scripts/read_cloudformation_stack_outputs.sh) - takes a CloudFormation stack name as input, and exports the outputs from that CloudFormation stack into shell in the `CFN_<stackname>_OutputKey=OutputValue` format. Any hyphens "-" in the stack name are converted to underscores "_"
