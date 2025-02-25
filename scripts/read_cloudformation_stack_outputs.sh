#!/bin/bash
set -euo pipefail

[[ ${BASH_SOURCE[0]} != "${0}" ]] || {
  echo "Error: Script must be sourced, not executed"
  exit 1
}

STACK_NAME="${1}"
configured_region="$(aws configure get region 2> /dev/null || true)"
REGION="${configured_region:-eu-west-2}"

function get_stack_outputs {

  local stack_name="$1"
  local output_format="table"
  if [ $# -gt 1 ]; then
    output_format="$2"
  fi

  aws cloudformation describe-stacks \
    --stack-name "${stack_name}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[].{key: OutputKey, value: OutputValue}' \
    --output "${output_format}"
}

eval "$(awk -v pipelineName="$(echo "${STACK_NAME}" | tr "-" "_")" '{ printf("export CFN_%s_%s=\"%s\"\n", pipelineName, $1, $2) }' <<< "$(get_stack_outputs "${STACK_NAME}" "text")")"
