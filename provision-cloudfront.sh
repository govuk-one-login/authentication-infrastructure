#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

function usage {
    cat <<USAGE
  Script to deploy CloudFront distribution and additional dependencies described in the the CloudFront header trust initiative

  Usage:
    $0 [-e|--environment <env name>] [-s|--sub-environment <sub-env name>] [-c|--certificates] [-d|--distribution <transitional|wildcard|live>] [-m|--monitoring] [-n|--notification] [-w|--waf]

  Options:
    -e, --environment        The environment you wish to deploy to i.e. build, staging, integration, or production
    -s, --sub-environment    (optional): include a second argument for sub-environment i.e. authdev1, authdev2
    -c, --certificates       Creates certificates in us-east-1 region for CloudFront Distribution
    -d, --distribution       Creates the CloudFront distribution
    -m, --monitoring         Deploys CloudFront Extended Monitoring configuration
    -n, --notification       Creates an SNS topic with Slack integration
    -w, --waf                Creates a WAF to attach to the CloudFront distribution
USAGE
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

PROVISION_WAF=false
PROVISION_CERTIFICATES=false
PROVISION_CLOUDFRONT_DISTRIBUTION=false
PROVISION_NOTIFICATION_STACK=false
PROVISION_MONITORING_STACK=false
SUB_ENVIRONMENT=""

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -e | --environment)
            ENVIRONMENT="${2}"
            shift
            ;;
        -s | --sub-environment)
            SUB_ENVIRONMENT="${2}"
            shift
            ;;
        -c | --certificates)
            PROVISION_CERTIFICATES=true
            ;;
        -d | --distribution)
            PROVISION_CLOUDFRONT_DISTRIBUTION=true
            CONFIGURATION="${2}"
            shift
            ;;
        -m | --monitoring)
            PROVISION_MONITORING_STACK=true
            ;;
        -n | --notification)
            PROVISION_NOTIFICATION_STACK=true
            ;;
        -w | --waf)
            PROVISION_WAF=true
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

echo "Deploying to ENVIRONMENT=${ENVIRONMENT}, SUB_ENVIRONMENT=${SUB_ENVIRONMENT}"

PARAMS_ENV=${ENVIRONMENT}
STACK_PREFIX="auth-fe"
if [ "${SUB_ENVIRONMENT}" != "" ]; then
    PARAMS_ENV=${SUB_ENVIRONMENT}
    STACK_PREFIX=${SUB_ENVIRONMENT}
fi
STACK_PREFIX_UNDERSCORE=$(echo "${STACK_PREFIX}" | tr "-" "_")

export AWS_ACCOUNT="di-authentication-${ENVIRONMENT}"
export AWS_PROFILE="di-authentication-${ENVIRONMENT}-AWSAdministratorAccess"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-false}"
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
function provision_waf {
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
}

# --------------------------------------------------------------
# auth-fe-cloudfront-certificate
#   Provisions signin-sp certificate for Cloudfront Distribution
#   no dependency
# --------------------------------------------------------------
function create_certificate {
    PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-certificate/parameters.json"
    HostedZoneID=${signin_sp_route53_hostedzone_id:-""}
    PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"HostedZoneID\",\"ParameterValue\":\"${HostedZoneID}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")
    TMP_PARAM_FILE=$(mktemp)
    echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

    aws configure set region us-east-1
    PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-certificate" certificate v1.1.1
}

# -----------------------------------------------------------
# auth-fe-cloudfront-live-certificate
#   Provisions signin certificate for Cloudfront Distribution
#   no dependency
# -----------------------------------------------------------
function create_live_certificate {
    PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-live-certificate/parameters.json"
    HostedZoneID=${signin_route53_hostedzone_id:-""}
    PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"HostedZoneID\",\"ParameterValue\":\"${HostedZoneID}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")
    TMP_PARAM_FILE=$(mktemp)
    echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

    aws configure set region us-east-1
    PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-live-certificate" certificate v1.1.1
}

# -------------------------------------------------------------------------
# auth-fe-cloudfront-wildcard-certificate
#   Provisions wildcard certificate that would be used ony during migration
#   no dependency
# -------------------------------------------------------------------------
function create_wildcard_certificate {
    PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-wildcard-certificate/parameters.json"

    aws configure set region us-east-1
    TEMPLATE_URL=file://certificate/template.yaml PARAMETERS_FILE=$PARAMETERS_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-wildcard-certificate" certificate LATEST
}

# ---------------------------------------------------------------------
# auth-fe-cloudfront
#   Creates the CloudFront distribution
#   depends on: auth-fe-cloudfront-waf, auth-fe-cloudfront-*certificate
# ---------------------------------------------------------------------
function provision_distribution {
    aws configure set region us-east-1

    # Feed output to the next stack
    # shellcheck disable=SC1091
    source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront-waf"
    webacl="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_waf_WAFv2WebACL"
    WAFv2WebACL=${!webacl:-"none"}

    # Feed output to the next stack
    # shellcheck disable=SC1091
    source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront-certificate"
    certarn="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_certificate_CertificateARN"
    CertificateARN=${!certarn:-""}

    # Feed output to the next stack
    # shellcheck disable=SC1091
    source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront-live-certificate"
    certarn="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_live_certificate_CertificateARN"
    LiveCertificateARN=${!certarn:-""}

    # Feed output to the next stack
    # shellcheck disable=SC1091
    source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront-wildcard-certificate"
    certarn="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_wildcard_certificate_CertificateARN"
    WildcardCertificateARN=${!certarn:-""}

    echo -e "CertificateARN=$CertificateARN\nLiveCertificateARN=$LiveCertificateARN\nWildcardCertificateARN=$WildcardCertificateARN"

    case "${CONFIGURATION}" in
        transitional)
            UseCertificateARN="${CertificateARN}"
            PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront/parameters.json"
            ;;
        wildcard)
            UseCertificateARN="${WildcardCertificateARN}"
            PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront/wildcard-parameters.json"
            ;;
        live)
            UseCertificateARN="${LiveCertificateARN}"
            PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront/live-parameters.json"
            ;;
        *)
            echo "Unknown distribution configuration: ${CONFIGURATION}"
            exit 1
            ;;
    esac

    OriginCloakingHeader=${signin_origin_cloaking_header:-""}
    PreviousOriginCloakingHeader=${previous_signin_origin_cloaking_header:-""}
    PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"CloudFrontWafACL\",\"ParameterValue\":\"${WAFv2WebACL}\"},
                            {\"ParameterKey\":\"CloudFrontCertArn\",\"ParameterValue\":\"${UseCertificateARN}\"},
                            {\"ParameterKey\":\"OriginCloakingHeader\",\"ParameterValue\":\"${OriginCloakingHeader}\"},
                            {\"ParameterKey\":\"PreviousOriginCloakingHeader\",\"ParameterValue\":\"${PreviousOriginCloakingHeader}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")
    TMP_PARAM_FILE=$(mktemp)
    echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

    aws configure set region eu-west-2
    if [ "${CONFIGURATION}" == "wildcard" ]; then
        TEMPLATE_URL=file://cloudfront-distribution/template.yaml PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront" cloudfront-distribution LATEST
    else
        PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront" cloudfront-distribution v1.6.0
    fi
}

# -----------------------------------------------------------------------------------
# auth-fe-cloudfront-notification
#   Creates a SNS topic with slack integration.
#   Topic is then used as CacheHitAlarmSNSTopicARN in the cloudfront-monitoring stack
#   no dependency
# -----------------------------------------------------------------------------------
function provision_notification {
    PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-notification/parameters.json"
    PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"AccountAlias\",\"ParameterValue\":\"${AWS_ACCOUNT}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")
    SAM_PARAMETERS=$( echo "$PARAMETERS" | jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' )
    TAGS=$(jq -r '.[] | "\(.Key)=\(.Value)" | gsub(" ";"-")' "configuration/${AWS_ACCOUNT}/tags.json")

    CONFIRM_CHANGESET_OPTION="--confirm-changeset"
    if [ "${AUTO_APPLY_CHANGESET}" == "true" ]; then
        CONFIRM_CHANGESET_OPTION="--no-confirm-changeset"
    fi

    aws configure set region us-east-1
    pushd alerts
    sam build
    # shellcheck disable=SC2086
    sam deploy \
        --stack-name "${STACK_PREFIX}-cloudfront-notification" \
        --resolve-s3 true \
        --s3-prefix "${STACK_PREFIX}-cloudfront-notification" \
        --region "us-east-1" \
        --capabilities "CAPABILITY_IAM" \
        $CONFIRM_CHANGESET_OPTION \
        --no-fail-on-empty-changeset \
        --parameter-overrides $SAM_PARAMETERS \
        --tags $TAGS
    popd
}

# -----------------------------------------------------------------
# auth-fe-cloudfront-monitoring
#   deploys CloudFront Extended Monitoring configuration
#   depends on: auth-fe-cloudfront, auth-fe-cloudfront-notification
# -----------------------------------------------------------------
function provision_monitoring {
    # Feed output to the next stack
    aws configure set region eu-west-2
    # shellcheck disable=SC1091
    source "./scripts/read_cloudformation_stack_outputs.sh" "${STACK_PREFIX}-cloudfront"
    cfdisId="CFN_${STACK_PREFIX_UNDERSCORE}_cloudfront_DistributionId"
    CloudFrontDistributionID=${!cfdisId:-""}

    # Feed output to the next stack
    aws configure set region us-east-1
    # shellcheck disable=SC1091
    source "./scripts/read_cloudformation_stack_outputs.sh" "auth-fe-cloudfront-notification"
    CacheHitAlarmSNSTopicARN=${CFN_auth_fe_cloudfront_notification_NotificationTopicArn:-"none"}

    PARAMETERS_FILE="configuration/${AWS_ACCOUNT}/${STACK_PREFIX}-cloudfront-monitoring/parameters.json"
    PARAMETERS=$(jq ". += [
                            {\"ParameterKey\":\"CloudfrontDistribution\",\"ParameterValue\":\"${CloudFrontDistributionID}\"},
                            {\"ParameterKey\":\"CacheHitAlarmSNSTopicARN\",\"ParameterValue\":\"${CacheHitAlarmSNSTopicARN}\"}
                        ] | tojson" -r "${PARAMETERS_FILE}")
    TMP_PARAM_FILE=$(mktemp)
    echo "$PARAMETERS" | jq -r > "$TMP_PARAM_FILE"

    aws configure set region us-east-1
    PARAMETERS_FILE=$TMP_PARAM_FILE ./provisioner.sh "${AWS_ACCOUNT}" "${STACK_PREFIX}-cloudfront-monitoring" cloudfront-monitoring-alarm v2.0.0
}

# --------------------
# Provision components
# --------------------
[ "$PROVISION_WAF" == "true" ] && provision_waf
[ "$PROVISION_CERTIFICATES" == "true" ] && {
    create_certificate
    create_live_certificate
    create_wildcard_certificate
}
[ "$PROVISION_CLOUDFRONT_DISTRIBUTION" == "true" ] && provision_distribution
[ "$PROVISION_NOTIFICATION_STACK" == "true" ] && provision_notification
[ "$PROVISION_MONITORING_STACK" == "true" ] && provision_monitoring

# -----
# reset
# -----
aws configure set region eu-west-2
