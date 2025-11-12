#!/bin/bash
# Deploy script for ad-hoc-tests CloudFormation stack
#
# NOTE: This script is for OLD ACCOUNTS ONLY (di-auth-development, gds-di-development)
#       NOT for the Secure Pipelines account
#
# Usage:
#   ./deploy.sh <dev|build>
#
# Examples:
#   ./deploy.sh dev    - Deploy to di-auth-development account (OLD)
#   ./deploy.sh build  - Deploy to gds-di-development account (OLD)
#
# The script will:
#   1. Authenticate with AWS SSO if not already authenticated
#   2. Deploy the ad-hoc-tests.yaml template with the appropriate parameters file
#   3. Create/update a stack named {environment}-ad-hoc-tests

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

if [ $# -eq 0 ]; then
  echo "Usage: $0 <dev|build>"
  exit 1
fi

ENV=$1

if [[ "${ENV}" == "dev" ]]; then
  export AWS_ACCOUNT=di-auth-development
  export AWS_PROFILE=di-auth-development-admin
  PARAMS_FILE="parameters-dev.json"
elif [[ "${ENV}" == "build" ]]; then
  # Must export profiles using after performing TEAM request using set-up-sso.sh in the authentication-api
  export AWS_ACCOUNT=gds-di-development
  export AWS_PROFILE=gds-di-development-AWSAdministratorAccess
  PARAMS_FILE="parameters-build.json"
else
  echo "Error: Invalid environment. Use 'dev' or 'build'"
  exit 1
fi

export AWS_REGION=eu-west-2

if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi

ENVIRONMENT=$(jq -r '.[] | select(.ParameterKey=="Environment") | .ParameterValue' "${PARAMS_FILE}")
STACK_NAME="${ENVIRONMENT}-ad-hoc-tests"

aws cloudformation deploy \
  --template-file ad-hoc-tests.yaml \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides file://"${PARAMS_FILE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${AWS_REGION}"

echo "Stack ${STACK_NAME} deployed successfully"
