#!/bin/bash
set -euo pipefail

[[ ${BASH_SOURCE[0]} != "${0}" ]] || {
  echo "Error: Script must be sourced, not executed"
  exit 1
}

ENVIRONMENT="${1}"
configured_region="$(aws configure get region 2> /dev/null || true)"
REGION="${configured_region:-eu-west-2}"

if [ "$ENVIRONMENT" = "dev" ]; then
  ENVIRONMENT="build"
fi

secrets="$(
  aws secretsmanager list-secrets \
    --filter "Key=\"name\",Values=\"/deploy/${ENVIRONMENT}/\"" --region "${REGION}" \
    | jq -r '.SecretList[]|[.ARN,(.Name|split("/")|last)]|@tsv'
)"

if [ -z "${secrets}" ]; then
  printf '!! ERROR: No secrets found for environment %s. Exiting.\n' "${ENVIRONMENT}" >&2
  exit 1
fi

echo "Reading secrets"
while IFS=$'\t' read -r arn name; do
  echo -n "."
  value=$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${arn}" | jq -r '.SecretString')
  name_in_underscore=$(echo "${name}" | tr "-" "_")
  export "${name_in_underscore}"="${value}"
done <<< "${secrets}"
