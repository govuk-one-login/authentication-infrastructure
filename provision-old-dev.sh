#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

# --------------------------
# dev account initialisation
# --------------------------
export AWS_ACCOUNT=di-auth-development
export AWS_PROFILE=di-auth-development-admin
# aws sso login --profile "${AWS_PROFILE}"

export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION="${SKIP_AWS_AUTHENTICATION:-true}"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"

# provision pipelines
# -------------------
# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "aws-signer"
SigningProfileArn=${CFN_aws_signer_SigningProfileArn:-"none"}
SigningProfileVersionArn=${CFN_aws_signer_SigningProfileVersionArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "container-signer"
ContainerSignerKmsKeyArn=${CFN_container_signer_ContainerSignerKmsKeyArn:-"none"}

# dev orch-stub pipeline
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/dev-orch-stub-pipeline/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                        {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                        {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")

TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" dev-orch-stub-pipeline sam-deploy-pipeline v2.68.4

# authdev1 orch-stub pipeline
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev1-sp-orch-stub-pipeline/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                        {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                        {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")

TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev1-sp-orch-stub-pipeline sam-deploy-pipeline v2.68.4
