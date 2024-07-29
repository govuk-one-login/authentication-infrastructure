#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

export AWS_ACCOUNT=di-authentication-build
export AWS_PROFILE=di-authentication-build-AWSAdministratorAccess
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"
aws sso login --profile "${AWS_PROFILE}"

# shellcheck source=/dev/null
source "./scripts/read_secrets.sh" "build"

# shellcheck source=/dev/null
source "./scripts/read_parameters.sh" "build"

# shallow clone templates from authentication repos
./sync-dependencies.sh

# --------------------------------------------------------
# auth-fe-cloudfront-waf
#   Creates a WAF to attach to the Cloudfront distribution
#   no dependency
# --------------------------------------------------------
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/auth-fe-cloudfront-waf/parameters.json"
RateLimitedEndpoints=$(echo "${rate_limited_endpoints:-""}" | sed -e 's/\"//g' -e 's/ //g' -e 's/\[//' -e 's/\]//') # trim quotes, spaces and [] brackets
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"RateLimitedEndpoints\",\"ParameterValue\":\"${RateLimitedEndpoints}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region us-east-1
TEMPLATE_URL=file://authentication-frontend/cloudformation/cloudfront-waf/template.yaml PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" auth-fe-cloudfront-waf waf LATEST

# Feed output to the next stack
# shellcheck source=/dev/null
source "./scripts/read_cloudformation_stack_outputs.sh" "auth-fe-cloudfront-waf"
WAFv2WebACL=${CFN_auth_fe_cloudfront_waf_WAFv2WebACL:-"none"}

# ----------------------------------------------------------
# auth-fe-cloudfront-certificate
#   Provision an ACM certificate for CloudFront distribution
#   no dependency
# ----------------------------------------------------------
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/auth-fe-cloudfront-certificate/parameters.json"
HostedZoneID=${signin_route53_hostedzone_id:-""}
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"HostedZoneID\",\"ParameterValue\":\"${HostedZoneID}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region us-east-1
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" auth-fe-cloudfront-certificate certificate v1.1.1

# Feed output to the next stack
# shellcheck source=/dev/null
source "./scripts/read_cloudformation_stack_outputs.sh" "auth-fe-cloudfront-certificate"
CertificateARN=${CFN_auth_fe_cloudfront_certificate_CertificateARN:-""}

# ------------------------------------------------------------------------------
# auth-fe-cloudfront
#   Creates the CloudFront distribution
#   depends on: auth-fe-cloudfront-certificate
# ------------------------------------------------------------------------------
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/auth-fe-cloudfront/parameters.json"
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
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" auth-fe-cloudfront cloudfront-distribution v1.6.0

# Feed output to the next stack
# shellcheck source=/dev/null
source "./scripts/read_cloudformation_stack_outputs.sh" "auth-fe-cloudfront"
CloudFrontDistributionID=${CFN_auth_fe_cloudfront_DistributionId:-""}

# ------------------------------------------------------
# auth-fe-cloudfront-monitoring
#   deploys CloudFront Extended Monitoring configuration
#   depends on: auth-fe-cloudfront
# ------------------------------------------------------
PARAMETERS_FILE="configuration/$AWS_ACCOUNT/auth-fe-cloudfront-monitoring/parameters.json"
PARAMETERS=$(jq ". += [
                        {\"ParameterKey\":\"CloudfrontDistribution\",\"ParameterValue\":\"${CloudFrontDistributionID}\"}
                    ] | tojson" -r "${PARAMETERS_FILE}")
TMP_PARAM_FILE=$(mktemp)
echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

aws configure set region us-east-1
PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" auth-fe-cloudfront-monitoring cloudfront-monitoring-alarm v2.0.0

# -----
# reset
# -----
aws configure set region eu-west-2
