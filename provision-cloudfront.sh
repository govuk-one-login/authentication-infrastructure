#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "At least one or at most two arguments must be supplied"
    echo "Argument 1: the env you wish to deploy to i.e. build, staging, integration or production"
    echo "Argument 2 (optional): include a second argument for sub-environment i.e. authdev1, authdev2"
    echo "Examples:"
    echo -e "\t$0 build"
    echo -e "\t$0 development authdev1"
    exit 1
fi

ENVIRONMENT=${1}
SUB_ENVIRONMENT=${2:-""}

PARAMS_ENV=${ENVIRONMENT}
STACK_PREFIX="auth-fe"
if [ "${SUB_ENVIRONMENT}" != "" ]; then
    PARAMS_ENV=${SUB_ENVIRONMENT}
    STACK_PREFIX=${SUB_ENVIRONMENT}
fi
STACK_PREFIX_UNDERSCORE=$(echo "${STACK_PREFIX}" | tr "-" "_")

export AWS_ACCOUNT="di-authentication-${ENVIRONMENT}"
export AWS_PROFILE="di-authentication-${ENVIRONMENT}-AWSAdministratorAccess"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"
aws sso login --profile "${AWS_PROFILE}"

# ----------------------------------
# export secrets and params in shell
# ----------------------------------
aws configure set region eu-west-2

# shellcheck disable=SC1091
source "./scripts/read_secrets.sh" "${PARAMS_ENV}"

# shellcheck disable=SC1091
source "./scripts/read_parameters.sh" "${PARAMS_ENV}"

# -------------------------------------------------
# shallow clone templates from authentication repos
# -------------------------------------------------
./sync-dependencies.sh

# --------------------------------------------------------
# auth-fe-cloudfront-waf
#   Creates a WAF to attach to the Cloudfront distribution
#   no dependency
# --------------------------------------------------------
PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-waf/parameters.json"
RateLimitedEndpoints=$(echo "${rate_limited_endpoints:-""}" | sed -e 's/\"//g' -e 's/ //g' -e 's/\[//' -e 's/\]//') # trim quotes, spaces and [] brackets
RateLimitedEndpointsRateLimitPeriod=${rate_limited_endpoints_rate_limit_period:-120}
RateLimitedEndpointsRequestsPerPeriod=${rate_limited_endpoints_requests_per_period:-100000}
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"RateLimitedEndpoints\",\"ParameterValue\":\"${RateLimitedEndpoints}\"},
                        {\"ParameterKey\":\"RateLimitedEndpointsRateLimitPeriod\",\"ParameterValue\":\"${RateLimitedEndpointsRateLimitPeriod}\"},
                        {\"ParameterKey\":\"RateLimitedEndpointsRequestsPerPeriod\",\"ParameterValue\":\"${RateLimitedEndpointsRequestsPerPeriod}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region us-east-1
TEMPLATE_URL=file://authentication-frontend/cloudformation/cloudfront-waf/template.yaml PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-waf" waf LATEST

# Feed output to the next stack
# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront-waf"
webacl="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_waf_WAFv2WebACL"
WAFv2WebACL=${!webacl:-"none"}

# ----------------------------------------------------------
# auth-fe-cloudfront-certificate
#   Provision an ACM certificate for CloudFront distribution
#   no dependency
# ----------------------------------------------------------
PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-certificate/parameters.json"
HostedZoneID=${signin_route53_hostedzone_id:-""}
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"HostedZoneID\",\"ParameterValue\":\"${HostedZoneID}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region us-east-1
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-certificate" certificate v1.1.1

# Feed output to the next stack
# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront-certificate"
certarn="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_certificate_CertificateARN"
CertificateARN=${!certarn:-""}

# ------------------------------------------------------------------------------
# auth-fe-cloudfront
#   Creates the CloudFront distribution
#   depends on: auth-fe-cloudfront-certificate
# ------------------------------------------------------------------------------
PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront/parameters.json"
OriginCloakingHeader=${signin_origin_cloaking_header:-""}
PreviousOriginCloakingHeader=${previous_signin_origin_cloaking_header:-""}
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"CloudFrontWafACL\",\"ParameterValue\":\"${WAFv2WebACL}\"},
                        {\"ParameterKey\":\"CloudFrontCertArn\",\"ParameterValue\":\"${CertificateARN}\"},
                        {\"ParameterKey\":\"OriginCloakingHeader\",\"ParameterValue\":\"${OriginCloakingHeader}\"},
                        {\"ParameterKey\":\"PreviousOriginCloakingHeader\",\"ParameterValue\":\"${PreviousOriginCloakingHeader}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region eu-west-2
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront" cloudfront-distribution v1.6.0

# Feed output to the next stack
# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront"
cfdisId="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_DistributionId"
CloudFrontDistributionID=${!cfdisId:-""}

# ------------------------------------------------------
# auth-fe-cloudfront-notification
#   Creates a SNS topic with slack integration.
#   Topic is then used as CacheHitAlarmSNSTopicARN in the cloudfront-monitoring stack
#   no dependency
# ----------------------------------------------------------
PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/auth-fe-cloudfront-notification/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"AccountAlias\",\"ParameterValue\":\"${AWS_ACCOUNT}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
SAM_PARAMETERS=$( echo "$PARAMETERS" | jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' )
TAGS=$(jq -r '.[] | "\(.Key)=\(.Value)" | gsub(" ";"-")' "configuration/${AWS_ACCOUNT}/tags.json")

aws configure set region us-east-1
pushd alerts
sam build
# shellcheck disable=SC2086
sam deploy \
    --stack-name "auth-fe-cloudfront-notification" \
    --resolve-s3 true \
    --s3-prefix "auth-fe-cloudfront-notification" \
    --region "us-east-1" \
    --capabilities "CAPABILITY_IAM" \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset \
    --parameter-overrides $SAM_PARAMETERS \
    --tags $TAGS
popd

# shellcheck disable=SC1091
source "./scripts/read_cloudformation_stack_outputs.sh" "auth-fe-cloudfront-notification"
CacheHitAlarmSNSTopicARN=${CFN_auth_fe_cloudfront_notification_NotificationTopicArn:-"none"}

# ------------------------------------------------------
# auth-fe-cloudfront-monitoring
#   deploys CloudFront Extended Monitoring configuration
#   depends on: auth-fe-cloudfront
# ------------------------------------------------------
PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-monitoring/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"CloudfrontDistribution\",\"ParameterValue\":\"${CloudFrontDistributionID}\"},
                        {\"ParameterKey\":\"CacheHitAlarmSNSTopicARN\",\"ParameterValue\":\"${CacheHitAlarmSNSTopicARN}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region us-east-1
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-monitoring" cloudfront-monitoring-alarm v2.0.0

# -----
# reset
# -----
aws configure set region eu-west-2
