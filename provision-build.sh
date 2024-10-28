#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

# ----------------------------
# build account initialisation
# ----------------------------
export AWS_ACCOUNT=di-authentication-build
export AWS_PROFILE=di-authentication-build-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"

export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION="${SKIP_AWS_AUTHENTICATION:-true}"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"

# provision base stacks
# ---------------------
./provisioner.sh "${AWS_ACCOUNT}" aws-signer signer v1.0.8
./provisioner.sh "${AWS_ACCOUNT}" container-signer container-signer v1.1.2
# ./provisioner.sh "${AWS_ACCOUNT}" ecr-image-scan-findings-logger ecr-image-scan-findings-logger v1.2.0
./provisioner.sh "${AWS_ACCOUNT}" github-identity github-identity v1.1.1

# ./provisioner.sh "${AWS_ACCOUNT}" alerting-integration alerting-integration v1.0.6
# ./provisioner.sh "${AWS_ACCOUNT}" api-gateway-logs api-gateway-logs v1.0.5
./provisioner.sh "${AWS_ACCOUNT}" build-notifications build-notifications v2.3.2
# ./provisioner.sh "${AWS_ACCOUNT}" certificate-expiry certificate-expiry v1.1.1
# ./provisioner.sh "${AWS_ACCOUNT}" checkov-hook checkov-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" infra-audit-hook infrastructure-audit-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" lambda-audit-hook lambda-audit-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" vpc vpc v2.5.2

./provisioner.sh "${AWS_ACCOUNT}" frontend-image-repository container-image-repository v1.3.2
./provisioner.sh "${AWS_ACCOUNT}" basic-auth-sidecar-image-repository container-image-repository v1.3.2
./provisioner.sh "${AWS_ACCOUNT}" service-down-page-image-repository container-image-repository v1.3.2

./provisioner.sh "${AWS_ACCOUNT}" acceptance-tests-image-repository test-image-repository v1.2.0

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "acceptance-tests-image-repository"
TestImageRepositoryUri=${CFN_acceptance_tests_image_repository_TestRunnerImageEcrRepositoryUri:-"none"}

# provision pipelines
# -------------------
# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "aws-signer"
SigningProfileArn=${CFN_aws_signer_SigningProfileArn:-"none"}
SigningProfileVersionArn=${CFN_aws_signer_SigningProfileVersionArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "container-signer"
ContainerSignerKmsKeyArn=${CFN_container_signer_ContainerSignerKmsKeyArn:-"none"}

PARAMETERS_FILE="configuration/$AWS_ACCOUNT/frontend-pipeline/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                        {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                        {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                        {\"ParameterKey\":\"TestImageRepositoryUri\",\"ParameterValue\":\"${TestImageRepositoryUri}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")

TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" frontend-pipeline sam-deploy-pipeline v2.68.0

# setting up domains
# ------------------
# # shallow clone templates from authentication repos
./sync-dependencies.sh

TEMPLATE_URL=file://authentication-frontend/cloudformation/domains/template.yaml ./provisioner.sh "${AWS_ACCOUNT}" dns-zones-and-records dns LATEST
