#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

function usage {
  cat << USAGE
  Script to bootstrap di-authentication-integration account

  Usage:
    $0 [-b|--base-stacks] [-n|--notification] [-p|--pipelines] [-v|--vpc] [-l|--live-zone-resources <zone-only|all>]

  Options:
    -b, --base-stacks                      Provision base stacks
    -n, --notification                     Creates a SNS topic with Slack integration
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
PROVISION_LIVE_HOSTED_ZONE_AND_RECORDS=false
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

# --------------------------------------------
# extract outputs from stacks in build account
# --------------------------------------------
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

# ----------------------------------------------
# extract outputs from stacks in staging account
# ----------------------------------------------
export AWS_ACCOUNT=di-authentication-staging
export AWS_PROFILE=di-authentication-staging-AWSAdministratorAccess

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "frontend-pipeline"
ArtifactSourceBucketArn=${CFN_frontend_pipeline_ArtifactPromotionBucketArn:-"none"}
ArtifactSourceBucketEventTriggerRoleArn=${CFN_frontend_pipeline_ArtifactPromotionBucketEventTriggerRoleArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "authentication-api-pipeline"
AuthenticationApiArtifactSourceBucketArn=${CFN_authentication_api_pipeline_ArtifactPromotionBucketArn:-"none"}
AuthenticationApiArtifactSourceBucketEventTriggerRoleArn=${CFN_authentication_api_pipeline_ArtifactPromotionBucketEventTriggerRoleArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "staging-orch-stub-pipeline"
OrchStubArtifactSourceBucketArn=${CFN_staging_orch_stub_pipeline_ArtifactPromotionBucketArn:-"none"}
OrchStubArtifactSourceBucketEventTriggerRoleArn=${CFN_staging_orch_stub_pipeline_ArtifactPromotionBucketEventTriggerRoleArn:-"none"}

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "smoke-test-pipeline"
SmoketestArtifactSourceBucketArn=${CFN_smoke_test_pipeline_ArtifactPromotionBucketArn:-"none"}
SmoketestArtifactSourceBucketEventTriggerRoleArn=${CFN_smoke_test_pipeline_ArtifactPromotionBucketEventTriggerRoleArn:-"none"}

# ----------------------------------
# Integration account initialisation
# ----------------------------------
export AWS_ACCOUNT=di-authentication-integration
export AWS_PROFILE=di-authentication-integration-AWSAdministratorAccess

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
  ./provisioner.sh "${AWS_ACCOUNT}" api-gateway-logs api-gateway-logs v1.0.5
  ./provisioner.sh "${AWS_ACCOUNT}" infra-audit-hook infrastructure-audit-hook LATEST
  ./provisioner.sh "${AWS_ACCOUNT}" lambda-audit-hook lambda-audit-hook LATEST
  ./provisioner.sh "${AWS_ACCOUNT}" build-notifications build-notifications v2.3.3

  TEMPLATE_BUCKET="backup-template-storage-templatebucket-747f3bzunrod" ./provisioner.sh "${AWS_ACCOUNT}" backup-monitoring backup-vault-monitoring LATEST
}

# -------------------
# provision vpc stack
# -------------------
function provision_vpc {
  export AWS_REGION="eu-west-2"

  VPC_TEMPLATE_VERSION="v2.10.0"
  ./provisioner.sh "${AWS_ACCOUNT}" vpc vpc "${VPC_TEMPLATE_VERSION}"
}

# -------------------
# provision pipelines
# -------------------
function provision_pipeline {
  PIPELINE_TEMPLATE_VERSION="v2.69.13"

  # frontend pipeline
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
  export AWS_REGION="eu-west-2"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" frontend-pipeline sam-deploy-pipeline "${PIPELINE_TEMPLATE_VERSION}"

  # backend pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/authentication-api-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                            {\"ParameterKey\":\"ArtifactSourceBucketArn\",\"ParameterValue\":\"${AuthenticationApiArtifactSourceBucketArn}\"},
                            {\"ParameterKey\":\"ArtifactSourceBucketEventTriggerRoleArn\",\"ParameterValue\":\"${AuthenticationApiArtifactSourceBucketEventTriggerRoleArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  export AWS_REGION="eu-west-2"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" authentication-api-pipeline sam-deploy-pipeline v2.76.0

  # orch-stub pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/integration-orch-stub-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                            {\"ParameterKey\":\"ArtifactSourceBucketArn\",\"ParameterValue\":\"${OrchStubArtifactSourceBucketArn}\"},
                            {\"ParameterKey\":\"ArtifactSourceBucketEventTriggerRoleArn\",\"ParameterValue\":\"${OrchStubArtifactSourceBucketEventTriggerRoleArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" integration-orch-stub-pipeline sam-deploy-pipeline v2.76.0

  # Smoke test pipeline
  PARAMETERS_FILE="configuration/$AWS_ACCOUNT/smoke-test-pipeline/parameters.json"
  PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"ContainerSignerKmsKeyArn\",\"ParameterValue\":\"${ContainerSignerKmsKeyArn}\"},
                            {\"ParameterKey\":\"SigningProfileArn\",\"ParameterValue\":\"${SigningProfileArn}\"},
                            {\"ParameterKey\":\"SigningProfileVersionArn\",\"ParameterValue\":\"${SigningProfileVersionArn}\"},
                            {\"ParameterKey\":\"ArtifactSourceBucketArn\",\"ParameterValue\":\"${SmoketestArtifactSourceBucketArn}\"},
                            {\"ParameterKey\":\"ArtifactSourceBucketEventTriggerRoleArn\",\"ParameterValue\":\"${SmoketestArtifactSourceBucketEventTriggerRoleArn}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")

  TMP_PARAM_FILE=$(mktemp)
  echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"
  export AWS_REGION="eu-west-2"
  PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" smoke-test-pipeline sam-deploy-pipeline v2.87.0
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
  source "./scripts/read_cloudformation_stack_outputs.sh" "build-notifications"
  NotificationTopicArn=${CFN_build_notifications_BuildNotificationDetailedTopicArn:-"none"}

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
[ "${PROVISION_LIVE_HOSTED_ZONE_AND_RECORDS}" == "true" ] && provision_live_hosted_zone_and_records
[ "${PROVISION_NOTIFICATION_STACK}" == "true" ] && provision_notification
[ "${PROVISION_PIPELINES}" == "true" ] && provision_pipeline
[ "${PROVISION_VPC}" == "true" ] && provision_vpc
