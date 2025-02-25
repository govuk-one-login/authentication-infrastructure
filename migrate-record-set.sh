#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

[ $# = 2 ] || {
  echo "Usage: $(basename "$0" .sh) newzoneid env(production or integration )" >&2
  exit 1
}

export AWS_PROFILE=di-authentication-"${2}"-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"
export AWS_REGION="eu-west-2"

# Create the DNS record in new Zone id
aws route53 change-resource-record-sets --hosted-zone-id "${1}" --change-batch file://dns-records-signin-"${2}".json
