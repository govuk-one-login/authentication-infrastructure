#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

[ $# = 2 ] || { echo "Usage: $(basename "$0" .sh) oldZoneid newzoneid" >&2; exit 1; }

# olld zone id Account profile 
export AWS_PROFILE=di-authentication-staging-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"
aws configure set region eu-west-2


# ------------------------------
# switch profile old Staging account 
# ------------------------------

#export AWS_ACCOUNT=di-auth-staging
#export AWS_PROFILE=di-auth-staging-AWSAdministratorAccess

#aws route53 list-resource-record-sets --hosted-zone-id "${1}" --output json  > list-records-"${1}".json

# --------------------------------------------
# Edit  the records in  file outputs as suggested in step 4 
# here https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-migrating.html#hosted-zones-migrating-edit-records
# --------------------------------------------

# ------------------------------
# switch profile new Staging account 
# ------------------------------
#export AWS_ACCOUNT=di-authentication-staging
#export AWS_PROFILE=di-authentication-staging-AWSAdministratorAccess

aws route53 change-resource-record-sets --hosted-zone-id "${2}" --change-batch file://list-records-"${1}".json