#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-}"
if [ -z "${ENVIRONMENT}" ]; then
  cat << USAGE
  Usage:
    $0 <ENVIRONMENT> <AWS_PROFILE> <INPUT_DIR>

  This is a helper script to populate Environment mappings.
  Sources of data:
    terraform <ENV>.tfvars from INPUT_DIR, or use the defaults hardcoded to this script
    aws cli various resources describe* command outputs

  Example run:
    $0 development di-auth-development-admin ../authentication-api/ci/terraform/oidc
USAGE
  exit 1
fi

export AWS_PROFILE="${2}"
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

if [ "${ENVIRONMENT}" = "development" ]; then
  ENVIRONMENT="dev"
fi

INPUT_DIR="${3}"

tables="
  access-token-store
  account-modifiers
  auth-code-store
  auth-session
  authentication-attempt
  client-registry
  common-passwords
  email-check-result
  id-reverification-state
  user-credentials
  user-profile
"

for table in ${tables}; do
  echo "$(echo "${table}" | gsed 's/-\([a-z]\)/\U\1/g')TableEncryptionKey: $(aws dynamodb describe-table --table-name "${ENVIRONMENT}-${table}" --query 'Table.SSEDescription.KMSMasterKeyArn' --output text)"
done

data="
    email_acct_creation_otp_code_ttl_duration 3600 |
    lockout_count_ttl                      900 |
    lockout_duration                       900 |
    otp_code_ttl_duration                  900 |
    reauth_enter_email_count_ttl           3600 |
    reduced_lockout_duration               900 |
    support_reauth_signout_enabled         false |
    terms_conditions_version               1.13 |
    test_clients_enabled                   false |
    use_strongly_consistent_reads          false |
"

TMP_PARAM_FILE=$(mktemp)
find "${INPUT_DIR}" -name "${ENVIRONMENT}.tfvars" -type f -exec cat '{}' \; > "$TMP_PARAM_FILE"

# shellcheck disable=SC2162,SC2086
while read -d"|" name value; do
  echo "$(echo ${name} | gsed 's/\_\([a-z]\)/\U\1/g'): $(grep "^\<${name}\> *=" $TMP_PARAM_FILE | awk '{print $NF}' | tr -d '"' || echo "${value}")"
done <<< $data

kms_keys="
    auditPayloadSigningKey                audit-payload-signing-key-alias |
    eventsTopicEncryptionKey              events-encryption-key-alias |
    experianPhoneCheckQueueEncryptionKey  oidc-experian-sqs-kms-alias |
    pendingEmailCheckQueueEncryptionKey   pending-email-check-queue-encryption-key |
"

# shellcheck disable=SC2162,SC2086
while read -d"|" name alias; do
  echo "${name}: $(aws kms describe-key --key-id "alias/${ENVIRONMENT}-${alias}" --query KeyMetadata.Arn --output text)"
done <<< ${kms_keys}
