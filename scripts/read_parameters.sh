#!/bin/bash
set -euo pipefail

[[ ${BASH_SOURCE[0]} != "${0}" ]] || {
  echo "Error: Script must be sourced, not executed"
  exit 1
}

ENVIRONMENT="${1}"
REGION="${AWS_REGION:-eu-west-2}"

if [ "$ENVIRONMENT" = "dev" ]; then
  ENVIRONMENT="build"
fi

parameters="$(
  aws ssm get-parameters-by-path \
    --recursive --path "/deploy/${ENVIRONMENT}" --region "${REGION}" \
    | jq -r '.Parameters[]|[(.Name|split("/")|last), .Value]|@tsv'
)"

if [ -z "${parameters}" ]; then
  printf '!! ERROR: No Parameter Score data found for environment %s. Exiting.\n' "${ENVIRONMENT}" >&2
  exit 1
fi

echo "Reading SSM parameters"
while IFS=$'\t' read -r name value; do
  echo -n "."
  name_in_underscore=$(echo "${name}" | tr "-" "_")
  export "${name_in_underscore}"="${value}"
done <<< "${parameters}"

echo "Parameters exported"
