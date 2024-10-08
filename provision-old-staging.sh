#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

# --------------------------------------------
# extract outputs from stacks in build account
# --------------------------------------------
export AWS_PROFILE=gds-di-development-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "signer"
SigningProfileArn=${CFN_signer_SigningProfileArn:-"none"}
SigningProfileVersionArn=${CFN_signer_SigningProfileVersionArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "container-signer"
ContainerSignerKmsKeyArn=${CFN_container_signer_ContainerSignerKmsKeyArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "build-sp-orch-stub-pipeline"
ArtifactSourceBucketArn=${CFN_build_sp_orch_stub_pipeline_ArtifactPromotionBucketArn:-"none"}
ArtifactSourceBucketEventTriggerRoleArn=${CFN_build_sp_orch_stub_pipeline_ArtifactPromotionBucketEventTriggerRoleArn:-"none"}

# ------------------------------
# staging account initialisation
# ------------------------------
export AWS_ACCOUNT=di-auth-staging
export AWS_PROFILE=di-auth-staging-AWSAdministratorAccess
# aws sso login --profile "${AWS_PROFILE}"

export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION="${SKIP_AWS_AUTHENTICATION:-true}"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"

# provision pipelines
# -------------------

# orch-stub pipeline
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/staging-sp-orch-stub-pipeline/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                        {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                        {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                        {\"ParameterKey\":\"ArtifactSourceBucketArn\",\"ParameterValue\":\"${ArtifactSourceBucketArn}\"},
                        {\"ParameterKey\":\"ArtifactSourceBucketEventTriggerRoleArn\",\"ParameterValue\":\"${ArtifactSourceBucketEventTriggerRoleArn}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")

TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" staging-sp-orch-stub-pipeline sam-deploy-pipeline v2.67.1
