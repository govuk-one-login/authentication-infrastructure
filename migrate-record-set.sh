#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

[ $# = 1 ] || { echo "Usage: $(basename "$0" .sh) newzoneid" >&1; exit 1; }

export AWS_PROFILE=di-authentication-production-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"
aws configure set region eu-west-2

# Created the DNS recird in new Zone id
aws route53 change-resource-record-sets --hosted-zone-id "${1}" --change-batch file://dns-records-signin-prod.json
