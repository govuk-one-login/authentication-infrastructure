#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-}"
if [ -z "${ENVIRONMENT}" ]; then
  cat << USAGE
  Usage:
    $0 <ENVIRONMENT> <AWS_PROFILE> <INPUT_DIR> <Optional: "readonly">

  This script bootstraps an environment by populating SSM parameter store with /deploy/<ENVIRONMENT>/* configurations.
  The default values mentioned in variables.tf have previously been extracted and hardcoded in "data".
  The script queries the INPUT_DIR and concatenates all the tfvar overrides into a single temporary file.
  If an override is found in the temporary file, it is used instead of the default.

  Example run:
    $0 development di-authentication-development-admin ../authentication-api/ci/terraform/oidc

    Readonly mode (prints the commands rather than executing them):
      $0 development di-authentication-development-admin ../authentication-api/ci/terraform/oidc readonly
USAGE
  exit 1
fi

PROFILE="${2}"
INPUT_DIR="${3}"
READONLY="${4:-}"

export AWS_PROFILE=${PROFILE}
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

if [ "${ENVIRONMENT}" = "development" ]; then
  ENVIRONMENT="dev"
fi

if [ "${READONLY}" = "readonly" ]; then
  CMD_PREFIX="echo"
fi

data="
  ipv_backend_uri                   undefined |
  ipv_audience                      undefined |
  ipv_auth_authorize_client_id      undefined |
  ipv_authorisation_uri             undefined |
  ipv_auth_authorize_callback_uri   undefined |
  evcs_audience                     undefined |
  auth_issuer_claim_for_evcs        undefined |
  ipv_jwks_url                       |
  ipv_auth_public_encryption_key_id  |
  ipv_jwks_call_enabled             false |
  reduced_lockout_duration                               900 |
  support_account_creation_count_ttl                     false |
  account_creation_lockout_count_ttl                     3600 |
  reauth_enter_sms_code_count_ttl                        3600 |
  code_max_retries_increased                             999999 |
  phone_checker_with_retry                               true |
  reauth_enter_auth_app_code_count_ttl                   3600 |
  terms_conditions_version                               1.13 |
  lockout_duration                                       900 |
  lockout_count_ttl                                      900 |
  incorrect_password_lockout_count_ttl                   7200 |
  support_reauth_signout_enabled                         false |
  authentication_attempts_service_enabled                false |
  reauth_enter_password_count_ttl                        3600 |
  use_strongly_consistent_reads                          false |
  otp_code_ttl_duration                                  900 |
  email_acct_creation_otp_code_ttl_duration              3600 |
  test_clients_enabled                                   false |
  account_intervention_service_abort_on_error            false |
  account_intervention_service_call_timeout              3000 |
  account_intervention_service_action_enabled            false |
  account_intervention_service_call_enabled              false |
  call_ticf_cri                                          false |
  ticf_cri_service_call_timeout                          2000 |
  verify_email_template_id                               b7dbb02f-941b-4d72-ad64-84cbe5d77c2e |
  verify_phone_number_template_id                        7dd388f1-e029-4fe7-92ff-18496dcb53e9 |
  mfa_sms_template_id                                    97b956c8-9a12-451a-994b-5d51741b63d4 |
  reset_password_template_id                             0aaf3ae8-1825-4528-af95-3093eb13fda0 |
  password_reset_confirmation_template_id                052d4e96-e6ca-4da2-b657-5649f28bd6c0 |
  account_created_confirmation_template_id               a15995f7-94a3-4a1b-9da0-54b1a8b5cc12 |
  reset_password_with_code_template_id                   503a8096-d22e-49dc-9f81-007cad156f01 |
  password_reset_confirmation_sms_template_id            ee9928fb-c716-4409-acd7-9b93fc02d0f8 |
  verify_change_how_get_security_codes_template_id       31259695-e0b8-4c1f-8392-995d5a3b6978 |
  change_how_get_security_codes_confirmation_template_id 10b2ebeb-16fb-450a-8dc3-5f94d2b7029f |
"

TMP_PARAM_FILE=$(mktemp)
find "${INPUT_DIR}" -name "${ENVIRONMENT}.tfvars" -type f -exec cat '{}' \; > "$TMP_PARAM_FILE"

echo "Writing SSM parameters"
# shellcheck disable=SC2162,SC2086
while read -d"|" name value; do
  export "${name}"="$(grep "^\<${name}\> *=" $TMP_PARAM_FILE | awk '{print $NF}' | tr -d '"' || echo "${value}")"
  ${CMD_PREFIX:-} aws ssm put-parameter --type "String" --name "/deploy/${ENVIRONMENT}/${name}" --value "${!name:- }" --region "${AWS_REGION}"
done <<< $data
echo "Parameters imported"
