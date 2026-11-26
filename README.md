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
| `-v`, `--vpc` | Provision VPC stack (includes spoke-vpc S3 template bucket and spoke-vpc stack for Transit Gateway peering) |
| `-l`, `--live-zone-resources <zone-only\|all>` | Provision live hosted zone, certificates and SSM params |
| `--pipeline-visualiser` | Deploy pipeline visualiser infrastructure (CodePipeline readonly role) |

Examples:

```bash
./provision-<env>.sh -b                        # Provision base stacks
./provision-<env>.sh -p                        # Provision pipelines
./provision-<env>.sh -v                        # Provision VPC + spoke-vpc (self-contained, no -b required)
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

### Spoke VPC

The `-v` flag provisions three stacks in order:

1. `vpc` — the main VPC (sourced from the shared template bucket)
2. `spoke-vpc-template-storage` — a dedicated S3 bucket used to store the spoke-vpc CloudFormation template. Created automatically from [`spoke-vpc/template-storage.yaml`](./spoke-vpc/template-storage.yaml). The bucket has:
   - KMS server-side encryption
   - All public access blocked
   - Versioning enabled
   - SSL-only bucket policy
3. `spoke-vpc` — the spoke VPC for Transit Gateway peering with the Auth legacy AWS account, sourced from [`spoke-vpc/template.yaml`](./spoke-vpc/template.yaml)

Both spoke-vpc templates live in the [`spoke-vpc/`](./spoke-vpc/) directory:

```
spoke-vpc/
├── template.yaml          # Spoke VPC CloudFormation template
└── template-storage.yaml  # S3 bucket for storing the spoke-vpc template
```

The `spoke-vpc-template-storage` bucket is deployed inline within `provision_vpc`, so running `-v` alone is fully self-contained — no need to run `-b` first.

### Helper scripts

[sync-dependencies.sh](./sync-dependencies.sh) - deploys and maintains a shallow copy of authentication-frontend repository, in order to source several cloudformation templates used in the provision scripts

[read_secrets.sh](./scripts/read_secrets.sh) - extracts all secrets stored in AWS Secrets Manager named as `/deploy/\${Environment}/secret-name` and export to shell as `secret-name=value`

[read_parameters.sh](./scripts/read_parameters.sh) - extracts all parameters stored in AWS Systems Manager Parameter store named as `/deploy/\${Environment}/param-name` and export to shell as `param-name=value`

Both secrets and parameters are then injected to the provisioner script

[read_cloudformation_stack_outputs.sh](./scripts/read_cloudformation_stack_outputs.sh) - takes a CloudFormation stack name as input, and exports the outputs from that CloudFormation stack into shell in the `CFN_<stackname>_OutputKey=OutputValue` format. Any hyphens "-" in the stack name are converted to underscores "_"

### Apex CloudFront Certificate

[provision-apex-cf-certificate.sh](./provision-apex-cf-certificate.sh) - provisions an ACM certificate in `us-east-1` (required by CloudFront) for the apex domain and stores the certificate ARN in SSM Parameter Store.

**What it does:**
1. Checks for an existing `PENDING_VALIDATION` or `ISSUED` ACM certificate for the apex domain in `us-east-1` — reuses it if found, otherwise requests a new one with DNS validation
2. If the certificate is pending validation, prints the CNAME `Name` and `Value` that must be **manually added** to the DNS hosted zone in the DNS account
3. Stores the certificate ARN in SSM at `/deploy/${ENVIRONMENT}/apex-certificate-arn` in `eu-west-2` for use by downstream stacks

**Usage:**

```bash
./provision-apex-cf-certificate.sh -e <environment>
```

| Option | Description |
|--------|-------------|
| `-e`, `--environment` | The environment to provision the certificate for (`dev`, `staging`, `integration`, `production`) |

**Examples:**

```bash
./provision-apex-cf-certificate.sh -e dev
./provision-apex-cf-certificate.sh -e staging
./provision-apex-cf-certificate.sh --environment production
```

**Domain mapping:**

| Environment | Domain |
|-------------|--------|
| `development` / `dev` | `dev.account.gov.uk` |
| `build` | `build.account.gov.uk` |
| `staging` | `staging.account.gov.uk` |
| `integration` | `integration.account.gov.uk` |
| `production` | `account.gov.uk` |

> **Note:** After running the script, if the certificate status is `PENDING_VALIDATION`, you must manually add the printed CNAME record to the DNS hosted zone before the certificate will be issued.
