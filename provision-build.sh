#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

function usage {
  cat << USAGE
  Script to bootstrap di-authentication-build account

  Usage:
    $0 [-b|--base-stacks] [-p|--pipelines] [-v|--vpc] [-l|--live-zone-resources <zone-only|all>]

  Options:
    -b, --base-stacks                      Provision base stacks
    -p, --pipelines                        Provision secure pipelines
    -v, --vpc                              Provision VPC stack
    -l, --live-zone-resources              Provision live hosted zone, certificates and SSM params
USAGE
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

PROVISION_BASE_STACKS=false
PROVISION_PIPELINES=false
PROVISION_LIVE_HOSTED_ZONE_AND_RECORDS=false
PROVISION_VPC=false

while [[ $# -gt 0 ]]; do
  case "${1}" in
    -b | --base-stacks)
      PROVISION_BASE_STACKS=true
      ;;
    -p | --pipelines)
      PROVISION_PIPELINES=true
      ;;
    -v | --vpc)
      PROVISION_VPC=true
      ;;
    -l | --live-zone-resources)
      PROVISION_LIVE_HOSTED_ZONE_AND_RECORDS=true
      DEPLOY_CONFIG=${2}
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

# ----------------------------
# build account initialisation
# ----------------------------
export AWS_ACCOUNT=di-authentication-build
export AWS_PROFILE=di-authentication-build-AWSAdministratorAccess
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "aws-signer"
SigningProfileArn=${CFN_aws_signer_SigningProfileArn:-"none"}
SigningProfileVersionArn=${CFN_aws_signer_SigningProfileVersionArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "container-signer"
ContainerSignerKmsKeyArn=${CFN_container_signer_ContainerSignerKmsKeyArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "acceptance-tests-image-repository"
TestImageRepositoryUri=${CFN_acceptance_tests_image_repository_TestRunnerImageEcrRepositoryUri:-"none"}

export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION="${SKIP_AWS_AUTHENTICATION:-true}"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-false}"

# -------------------------------------------------
# shallow clone templates from authentication repos
# -------------------------------------------------
./sync-dependencies.sh

# ---------------------
# provision base stacks
# ---------------------
function provision_base_stacks {
  export AWS_REGION="eu-west-2"
  ./provisioner.sh "${AWS_ACCOUNT}" aws-signer signer v1.0.8
  ./provisioner.sh "${AWS_ACCOUNT}" container-signer container-signer v1.1.2
  # ./provisioner.sh "${AWS_ACCOUNT}" ecr-image-scan-findings-logger ecr-image-scan-findings-logger v1.2.0
  ./provisioner.sh "${AWS_ACCOUNT}" github-identity github-identity v1.1.1

  # ./provisioner.sh "${AWS_ACCOUNT}" alerting-integration alerting-integration v1.0.6
  # ./provisioner.sh "${AWS_ACCOUNT}" api-gateway-logs api-gateway-logs v1.0.5
  ./provisioner.sh "${AWS_ACCOUNT}" build-notifications build-notifications v2.3.3
  # ./provisioner.sh "${AWS_ACCOUNT}" certificate-expiry certificate-expiry v1.1.1
  # ./provisioner.sh "${AWS_ACCOUNT}" checkov-hook checkov-hook LATEST
  ./provisioner.sh "${AWS_ACCOUNT}" infra-audit-hook infrastructure-audit-hook LATEST
  ./provisioner.sh "${AWS_ACCOUNT}" lambda-audit-hook lambda-audit-hook LATEST

  CONTAINER_IMAGE_TEMPLATE_VERSION="v2.0.1"
  ./provisioner.sh "${AWS_ACCOUNT}" frontend-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" service-down-page-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"

  ./provisioner.sh "${AWS_ACCOUNT}" acceptance-tests-image-repository test-image-repository v1.2.0
}

# -------------------
# provision vpc stack
# -------------------
function provision_vpc {
  export AWS_REGION="eu-west-2"

  VPC_TEMPLATE_VERSION="v2.7.0"
  ./provisioner.sh "${AWS_ACCOUNT}" vpc vpc "${VPC_TEMPLATE_VERSION}"
}

# -------------------
# provision pipelines
# -------------------
function provision_pipeline {
  PIPELINE_TEMPLATE_VERSION="v2.69.13"
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/frontend-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                            {\"ParameterKey\":\"TestImageRepositoryUri\",\"ParameterValue\":\"${TestImageRepositoryUri}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  export AWS_REGION="eu-west-2"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" frontend-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # Build ipv-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/build-ipv-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" build-ipv-stub-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # orch-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/build-orch-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" build-orch-stub-pipeline sam-deploy-pipeline v2.67.1
}

# ------------------
# setting up domains
# ------------------
function provision_live_hosted_zone_and_records {
  case "${DEPLOY_CONFIG}" in
    zone-only)
      PARAMETERS_FILE="configuration/$AWS_ACCOUNT/hosted-zones-and-records/zone-only-parameters.json"
      ;;
    all)
      PARAMETERS_FILE="configuration/$AWS_ACCOUNT/hosted-zones-and-records/parameters.json"
      ;;
    *)
      echo "Unknown live domain deploy configuration: $DEPLOY_CONFIG"
      usage
      exit 1
      ;;
  esac

  # deploy signin domain resources
  export AWS_REGION="eu-west-2"
  PARAMETERS_FILE=$PARAMETERS_FILE TEMPLATE_URL=file://authentication-frontend/cloudformation/domains/template.yaml ./provisioner.sh "${AWS_ACCOUNT}" hosted-zones-and-records dns LATEST
}

# --------------------
# Provision components
# --------------------
[ "${PROVISION_BASE_STACKS}" == "true" ] && provision_base_stacks
[ "${PROVISION_PIPELINES}" == "true" ] && provision_pipeline
[ "${PROVISION_LIVE_HOSTED_ZONE_AND_RECORDS}" == "true" ] && provision_live_hosted_zone_and_records
[ "${PROVISION_VPC}" == "true" ] && provision_vpc
