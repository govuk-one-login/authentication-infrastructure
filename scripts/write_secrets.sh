#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-}"
if [ -z "${ENVIRONMENT}" ]; then
  cat << USAGE
  Usage:
    $0 <ENVIRONMENT> <OLD_ACCOUNT AWS_PROFILE> <NEW_ACCOUNT AWS_PROFILE> <Optional: "readonly">

  This script bootstraps an environment by populating Secrets Manager with /deploy/<ENVIRONMENT>/* secrets.
  Secrets are fetched from the OLD_ACCOUNT and then written in the NEW_ACCOUNT.

  Example run:
    $0 development di-auth-development-admin di-authentication-development-admin

    Readonly mode (prints the commands rather than executing them):
      $0 development di-auth-development-admin di-authentication-development-admin readonly
USAGE
  exit 1
fi

OLD_ACCOUNT_PROFILE="${2}"
NEW_ACCOUNT_PROFILE="${3}"
READONLY="${4:-}"

if [ "$ENVIRONMENT" = "development" ]; then
  ENVIRONMENT="dev"
fi

if [ "${READONLY}" = "readonly" ]; then
  CMD_PREFIX="echo"
fi

export AWS_PROFILE=${OLD_ACCOUNT_PROFILE}
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

old_account_id=$(aws sts get-caller-identity --query Account --output text)

kms_keys="
  ipv_reverification_request_signing_key ipv_reverification_request_signing_key |
  mfa-reset-token-signing-key-ecc-alias mfa_reset_token_signing_key_ecc |
"

# shellcheck disable=SC2162,SC2086
while read -d"|" alias secretname; do
  export "${secretname}"="$(aws kms list-aliases --query "Aliases[?AliasName=='alias/${ENVIRONMENT}-${alias}'].[TargetKeyId]" --output text)"
done <<< ${kms_keys}

secrets="
  account_intervention_service_uri |
  ticf_cri_service_uri |
  notify_api_key |
  notify_test_destinations |
  test_client_verify_email_otp |
  test_client_verify_phone_number_otp |
"

# shellcheck disable=SC2162,SC2086
while read -d"|" name; do
  echo "reading /deploy/${ENVIRONMENT}/${name}"
  export "${name}"="$(aws secretsmanager get-secret-value --secret-id "/deploy/${ENVIRONMENT}/${name}" --region "${AWS_REGION}" | jq -r '.SecretString')"
done <<< ${secrets}

case "${ENVIRONMENT}" in
  dev | build)
    interventions_api=$(aws apigateway get-rest-apis --query "items[?name=='${ENVIRONMENT}-di-interventions-api-stub'].[id]" --output text)
    ticf_cri_api=$(aws apigateway get-rest-apis --query "items[?name=='${ENVIRONMENT}-di-ticf-cri-stub'].[id]" --output text)
    ;;
  *)
    old_vpc_endpoint=$(aws ec2 describe-vpc-endpoints --filters 'Name=service-name,Values=com.amazonaws.eu-west-2.execute-api' --query 'VpcEndpoints[].VpcEndpointId' --output text)
    ;;
esac

export AWS_PROFILE=${NEW_ACCOUNT_PROFILE}
vpc_endpoint=$(aws ec2 describe-vpc-endpoints --filters 'Name=service-name,Values=com.amazonaws.eu-west-2.execute-api' --query 'VpcEndpoints[].VpcEndpointId' --output text)

case "${ENVIRONMENT}" in
  dev | build)
    account_intervention_service_uri="https://${interventions_api}-${vpc_endpoint}.execute-api.eu-west-2.amazonaws.com/${ENVIRONMENT}"
    ticf_cri_service_uri="https://${ticf_cri_api}-${vpc_endpoint}.execute-api.eu-west-2.amazonaws.com/${ENVIRONMENT}"
    ;;
  *)
    account_intervention_service_uri=${account_intervention_service_uri/"$old_vpc_endpoint"/"$vpc_endpoint"}
    ticf_cri_service_uri=${ticf_cri_service_uri/"$old_vpc_endpoint"/"$vpc_endpoint"}
    ;;
esac

echo -e "\nWriting secrets"
# shellcheck disable=SC2162,SC2086
while read -d"|" alias secretname; do
  echo -n "."
  ${CMD_PREFIX:-} aws secretsmanager create-secret --name "/deploy/${ENVIRONMENT}/${secretname}" --secret-string "arn:aws:kms:${AWS_REGION}:${old_account_id}:key/${!secretname}" --region "${AWS_REGION}"
done <<< ${kms_keys}

# shellcheck disable=SC2162,SC2086
while read -d"|" name; do
  echo -n "."
  ${CMD_PREFIX:-} aws secretsmanager create-secret --name "/deploy/${ENVIRONMENT}/${name}" --secret-string "${!name:- }" --region "${AWS_REGION}"
done <<< ${secrets}
echo "Secrets imported"
