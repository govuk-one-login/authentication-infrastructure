#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

# --------------------------------------------
# extract outputs from stacks in build account
# --------------------------------------------
export AWS_PROFILE=di-authentication-build-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "aws-signer"
SigningProfileArn=${CFN_aws_signer_SigningProfileArn:-"none"}
SigningProfileVersionArn=${CFN_aws_signer_SigningProfileVersionArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "container-signer"
ContainerSignerKmsKeyArn=${CFN_container_signer_ContainerSignerKmsKeyArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "frontend-pipeline"
ArtifactSourceBucketArn=${CFN_frontend_pipeline_ArtifactPromotionBucketArn:-"none"}
ArtifactSourceBucketEventTriggerRoleArn=${CFN_frontend_pipeline_ArtifactPromotionBucketEventTriggerRoleArn:-"none"}

# ------------------------------
# Staging account initialisation
# ------------------------------
export AWS_ACCOUNT=di-authentication-staging
export AWS_PROFILE=di-authentication-staging-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"

export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION="${SKIP_AWS_AUTHENTICATION:-true}"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"

# provision base stacks
# ---------------------
# ./provisioner.sh "${AWS_ACCOUNT}" alerting-integration alerting-integration v1.0.6
# ./provisioner.sh "${AWS_ACCOUNT}" api-gateway-logs api-gateway-logs v1.0.5
# ./provisioner.sh "${AWS_ACCOUNT}" build-notifications build-notifications v2.3.1
# ./provisioner.sh "${AWS_ACCOUNT}" certificate-expiry certificate-expiry v1.1.1
# ./provisioner.sh "${AWS_ACCOUNT}" checkov-hook checkov-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" infra-audit-hook infrastructure-audit-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" lambda-audit-hook lambda-audit-hook LATEST

./provisioner.sh "${AWS_ACCOUNT}" vpc vpc v2.5.2

# provision pipelines
# -------------------
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/frontend-pipeline/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                        {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                        {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                        {\"ParameterKey\":\"ArtifactSourceBucketArn\",\"ParameterValue\":\"${ArtifactSourceBucketArn}\"},
                        {\"ParameterKey\":\"ArtifactSourceBucketEventTriggerRoleArn\",\"ParameterValue\":\"${ArtifactSourceBucketEventTriggerRoleArn}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")

TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" frontend-pipeline sam-deploy-pipeline v2.66.0

# setting up domains
# ------------------
# shallow clone templates from authentication repos
./sync-dependencies.sh

TEMPLATE_URL=file://authentication-frontend/cloudformation/domains/template.yaml ./provisioner.sh "${AWS_ACCOUNT}" dns-zones-and-records dns LATEST
