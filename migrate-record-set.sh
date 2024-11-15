#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

# --------------------------------------------
# extract outputs from stacks in build account
# --------------------------------------------
export AWS_PROFILE=di-auth-staging
aws sso login --profile "${AWS_PROFILE}"
aws configure set region eu-west-2


aws route53 list-resource-record-sets --hosted-zone-id "${1}" --output json  > list-records-"${1}".json