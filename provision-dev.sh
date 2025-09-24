#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

function usage {
  cat << USAGE
  Script to bootstrap di-authentication-development account

  Usage:
    $0 [-b|--base-stacks] [-n|--notification] [-p|--pipelines] [-v|--vpc] [-z|--hosted-zone-resources]

  Options:
    -b, --base-stacks                      Provision base stacks
    -n, --notification                     Creates a SNS topic with Slack integration
    -p, --pipelines                        Provision secure pipelines
    -v, --vpc                              Provision VPC stack
    -z, --hosted-zone-resources            Provision hosted zone, certificates and SSM params
USAGE
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

PROVISION_BASE_STACKS=false
PROVISION_HOSTED_ZONE_AND_RECORDS=false
PROVISION_NOTIFICATION_STACK=false
PROVISION_PIPELINES=false
PROVISION_VPC=false

while [[ $# -gt 0 ]]; do
  case "${1}" in
    -b | --base-stacks)
      PROVISION_BASE_STACKS=true
      ;;
    -n | --notification)
      PROVISION_NOTIFICATION_STACK=true
      ;;
    -p | --pipelines)
      PROVISION_PIPELINES=true
      ;;
    -v | --vpc)
      PROVISION_VPC=true
      ;;
    -z | --hosted-zone-resources)
      PROVISION_HOSTED_ZONE_AND_RECORDS=true
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
export AWS_ACCOUNT=di-authentication-development
export AWS_PROFILE=di-authentication-development-AWSAdministratorAccess
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

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
  ./provisioner.sh "${AWS_ACCOUNT}" github-identity github-identity v1.1.1
  ./provisioner.sh "${AWS_ACCOUNT}" container-signer container-signer v1.1.2

  ./provisioner.sh "${AWS_ACCOUNT}" infra-audit-hook infrastructure-audit-hook LATEST
  ./provisioner.sh "${AWS_ACCOUNT}" lambda-audit-hook lambda-audit-hook LATEST

  ./provisioner.sh "${AWS_ACCOUNT}" build-notifications build-notifications v2.3.3

  ./provisioner.sh "${AWS_ACCOUNT}" api-gateway-logs api-gateway-logs v1.0.5

  CONTAINER_IMAGE_TEMPLATE_VERSION="v3.0.0"
  # NOTE: tag immutability is manually disabled for these ecr repositories
  ./provisioner.sh "${AWS_ACCOUNT}" frontend-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" frontend-apitest-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" service-down-page-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" acceptance-tests-image-repository test-image-repository v1.2.0

  # NOTE: tag immutability is manually disabled for these ecr repositories
  ./provisioner.sh "${AWS_ACCOUNT}" authdev1-frontend-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" authdev1-service-down-page-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"

  # NOTE: tag immutability is manually disabled for these ecr repositories
  ./provisioner.sh "${AWS_ACCOUNT}" authdev2-frontend-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" authdev2-service-down-page-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"

  # NOTE: tag immutability is manually disabled for these ecr repositories
  ./provisioner.sh "${AWS_ACCOUNT}" authdev3-frontend-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"
  ./provisioner.sh "${AWS_ACCOUNT}" authdev3-service-down-page-image-repository container-image-repository "${CONTAINER_IMAGE_TEMPLATE_VERSION}"

  TEMPLATE_URL=file://deployment-configs/template.yaml ./provisioner.sh "${AWS_ACCOUNT}" deployment-configs deployment-configs LATEST
}

# -------------------
# provision vpc stack
# -------------------
function provision_vpc {
  export AWS_REGION="eu-west-2"

  VPC_TEMPLATE_VERSION="v2.9.2"
  ./provisioner.sh "${AWS_ACCOUNT}" vpc vpc "${VPC_TEMPLATE_VERSION}"
}

# -------------------
# provision pipelines
# -------------------
function provision_pipeline {
  PIPELINE_TEMPLATE_VERSION="v2.69.13"
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

  # dev-frontend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/frontend-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                            {\"ParameterKey\":\"TestImageRepositoryUri\",\"ParameterValue\":\"${TestImageRepositoryUri}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" frontend-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # dev-backend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authentication-api-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                            {\"ParameterKey\":\"TestImageRepositoryUri\",\"ParameterValue\":\"${TestImageRepositoryUri}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authentication-api-pipeline sam-deploy-pipeline v2.76.0

  # authdev1-frontend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev1-frontend-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev1-frontend-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # authdev1-backend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev1-api-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev1-api-pipeline sam-deploy-pipeline v2.76.0

  # authdev2-frontend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev2-frontend-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev2-frontend-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # authdev2-backend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev2-api-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev2-api-pipeline sam-deploy-pipeline v2.76.0

  # authdev3-frontend
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev3-frontend-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev3-frontend-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # dev ipv-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/dev-ipv-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" dev-ipv-stub-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # authdev1 ipv-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev1-ipv-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev1-ipv-stub-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # authdev2 ipv-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev2-ipv-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev2-ipv-stub-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # dev orch-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/dev-orch-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                          {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                          {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                          {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                      ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" dev-orch-stub-pipeline sam-deploy-pipeline v2.76.0

  # authdev1 orch-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev1-orch-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                          {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                          {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                          {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                      ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev1-orch-stub-pipeline sam-deploy-pipeline v2.76.0

  # authdev2 orch-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev2-orch-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                          {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                          {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                          {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                      ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev2-orch-stub-pipeline sam-deploy-pipeline v2.76.0

  # Dev Smoke test pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/smoke-test-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" dev-smoke-test-pipeline sam-deploy-pipeline v2.87.0

  # AutDev1 Account Management pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev1-account-management-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev1-account-management-pipeline sam-deploy-pipeline v2.87.0

  # AutDev2 Account Management pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev2-account-management-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev2-account-management-pipeline sam-deploy-pipeline v2.87.0

  # AutDev3 Account Management pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authdev3-account-management-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authdev3-account-management-pipeline sam-deploy-pipeline v2.87.0

}

# ------------------
# setting up domains
# ------------------
function provision_hosted_zone_and_records {
  export AWS_REGION="eu-west-2"
  TEMPLATE_URL=file://authentication-frontend/cloudformation/domains/template.yaml ./provisioner.sh "${AWS_ACCOUNT}" dns-zones-and-records dns LATEST
}

# --------------------------------------------
#   Creates a SNS topic with slack integration
#   Sets up an alarm for lambda code storage
# --------------------------------------------
function provision_notification {
  SAM_PARAMETERS=$(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "configuration/${AWS_ACCOUNT}/cloudwatch-alarm-notification/parameters.json")
  TAGS=$(jq -r '.[] | "\(.Key)=\(.Value)" | gsub(" ";"-")' "configuration/${AWS_ACCOUNT}/tags.json")

  CONFIRM_CHANGESET_OPTION="--confirm-changeset"
  if [ "${AUTO_APPLY_CHANGESET}" == "true" ]; then
    CONFIRM_CHANGESET_OPTION="--no-confirm-changeset"
  fi

  export AWS_REGION="eu-west-2"
  pushd alerts
  sam build
  # shellcheck disable=SC2086
  sam deploy \
    --stack-name "cloudwatch-alarm-notification" \
    --resolve-s3 true \
    --s3-prefix "cloudwatch-alarm-notification" \
    --region "eu-west-2" \
    --capabilities "CAPABILITY_IAM" \
    $CONFIRM_CHANGESET_OPTION \
    --no-fail-on-empty-changeset \
    --parameter-overrides $SAM_PARAMETERS \
    --tags $TAGS
  popd

  # shellcheck disable=SC1091
  source "./scripts/read_cloudformation_stack_outputs.sh" "cloudwatch-alarm-notification"
  NotificationTopicArn=${CFN_cloudwatch_alarm_notification_NotificationTopicArn:-"none"}

  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/lambda-code-storage-alarm/parameters.json"
  PARAMETERS=$(jq ". += [
                          {\"ParameterKey\":\"CodeStorageSNSTopicARN\",\"ParameterValue\":\"${NotificationTopicArn}\"}
                      ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" lambda-code-storage-alarm cloudwatch-alarm-stack v0.0.7
}

# --------------------
# Provision components
# --------------------
[ "${PROVISION_BASE_STACKS}" == "true" ] && provision_base_stacks
[ "${PROVISION_HOSTED_ZONE_AND_RECORDS}" == "true" ] && provision_hosted_zone_and_records
[ "${PROVISION_NOTIFICATION_STACK}" == "true" ] && provision_notification
[ "${PROVISION_PIPELINES}" == "true" ] && provision_pipeline
[ "${PROVISION_VPC}" == "true" ] && provision_vpc
