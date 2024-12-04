#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

[ $# = 2 ] || { echo "Usage: $(basename "$0" .sh) newzoneid env(staging or build)" >&2; exit 1; }

# olld zone id Account profile
export AWS_PROFILE=di-authentication-"${2}"-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"
aws configure set region eu-west-2


aws route53 change-resource-record-sets --hosted-zone-id "${1}" --change-batch file://dns-records-signin-"${2}".json
