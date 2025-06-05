#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1}"
PROFILE="${2}"

export AWS_PROFILE=${PROFILE}
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

if [ "${ENVIRONMENT}" = "development" ]; then
  ENVIRONMENT="dev"
fi

data="
    terms_conditions_version                          1.13 |
    lockout_duration                                  600 |
    lockout_count_ttl                                 600 |
    incorrect_password_lockout_count_ttl              600 |
    support_reauth_signout_enabled                    true |
    authentication_attempts_service_enabled           true |
    reauth_enter_password_count_ttl                   120 |
    use_strongly_consistent_reads                     true |
    otp_code_ttl_duration                      600 |
    email_acct_creation_otp_code_ttl_duration  600 |
    test_clients_enabled                       true |
    account_intervention_service_abort_on_error            true |
    account_intervention_service_call_timeout              3000 |
    account_intervention_service_action_enabled            true |
    account_intervention_service_call_enabled              true |
    call_ticf_cri                                          true |
    invoke_ticf_cri_lambda                                 true |
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

echo "Writing SSM parameters"
# shellcheck disable=SC2162,SC2086
while read -d"|" name value; do
  echo -n "."
  aws ssm put-parameter --type "String" --name "/deploy/${ENVIRONMENT}/${name}" --value "${value}" --region "${AWS_REGION}"
done <<< $data

echo "Parameters imported"
