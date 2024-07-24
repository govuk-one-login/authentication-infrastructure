#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

export AWS_ACCOUNT=di-authentication-build
export AWS_PROFILE=di-authentication-build-AWSAdministratorAccess
aws sso login --profile "${AWS_PROFILE}"

export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION="${SKIP_AWS_AUTHENTICATION:-true}"
export AUTO_APPLY_CHANGESET="${AUTO_APPLY_CHANGESET:-true}"

cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 || exit

./provisioner.sh "${AWS_ACCOUNT}" aws-signer signer v1.0.8
./provisioner.sh "${AWS_ACCOUNT}" container-signer container-signer v1.1.2
# ./provisioner.sh "${AWS_ACCOUNT}" ecr-image-scan-findings-logger ecr-image-scan-findings-logger v1.2.0
./provisioner.sh "${AWS_ACCOUNT}" github-identity github-identity v1.1.1

# ./provisioner.sh "${AWS_ACCOUNT}" alerting-integration alerting-integration v1.0.6
# ./provisioner.sh "${AWS_ACCOUNT}" api-gateway-logs api-gateway-logs v1.0.5
# ./provisioner.sh "${AWS_ACCOUNT}" build-notifications build-notifications v2.3.1
# ./provisioner.sh "${AWS_ACCOUNT}" certificate-expiry certificate-expiry v1.1.1
# ./provisioner.sh "${AWS_ACCOUNT}" checkov-hook checkov-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" infra-audit-hook infrastructure-audit-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" lambda-audit-hook lambda-audit-hook LATEST
./provisioner.sh "${AWS_ACCOUNT}" vpc vpc v2.5.2

./provisioner.sh "${AWS_ACCOUNT}" frontend-image-repository container-image-repository v1.3.2
./provisioner.sh "${AWS_ACCOUNT}" basic-auth-sidecar-image-repository container-image-repository v1.3.2
./provisioner.sh "${AWS_ACCOUNT}" service-down-page-image-repository container-image-repository v1.3.2

./provisioner.sh "${AWS_ACCOUNT}" frontend-pipeline sam-deploy-pipeline v2.60.2

TEMPLATE_URL=file://authentication-frontend/cloudformation/domains/template.yaml ./provisioner.sh "${AWS_ACCOUNT}" dns-zones-and-records dns LATEST
