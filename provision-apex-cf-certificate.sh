#!/bin/bash
set -euo pipefail

# Ensure we are in the directory of the script
cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 || exit

function usage {
  cat << USAGE
  Script to provision the Apex CloudFront certificate in us-east-1 via ACM CLI.
  DNS validation CNAMEs must be added manually to the hosted zone in the DNS account.

  Usage:
    $0 [-e|--environment <env name>]

  Options:
    -e, --environment   The environment you wish to deploy to i.e. dev, staging, integration, or production
USAGE
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    -e | --environment)
      ENVIRONMENT="${2}"
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

echo "Provisioning apex certificate for ENVIRONMENT=${ENVIRONMENT}"

export AWS_ACCOUNT="di-authentication-${ENVIRONMENT}"

if [[ ${ENVIRONMENT} == "development" ]]; then
  export AWS_PROFILE="di-authentication-development-AdministratorAccessPermission"
else
  export AWS_PROFILE="di-authentication-${ENVIRONMENT}-ApprovedAdmin"
fi

if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi

export AWS_REGION="eu-west-2"

if [[ ${ENVIRONMENT} == "production" ]]; then
  SERVICE_DOMAIN="account.gov.uk"
elif [[ ${ENVIRONMENT} == "development" ]]; then
  SERVICE_DOMAIN="dev.account.gov.uk"
else
  SERVICE_DOMAIN="${ENVIRONMENT}.account.gov.uk"
fi

echo "Using ServiceDomain=${SERVICE_DOMAIN}"

if [[ ${ENVIRONMENT} == "development" ]]; then
  ENVIRONMENT="dev"
fi

# -----------------------------------------------------------
# Request certificate via ACM CLI (us-east-1 required for Apex page CloudFront).
# -----------------------------------------------------------

export AWS_REGION="us-east-1"

# Re-use an existing PENDING_VALIDATION or ISSUED cert if one already exists
EXISTING_CERT_ARN=$(aws acm list-certificates \
  --region us-east-1 \
  --query "CertificateSummaryList[?DomainName==\`${SERVICE_DOMAIN}\`].CertificateArn" \
  --output text)

if [[ -n ${EXISTING_CERT_ARN} ]]; then
  CERT_STATUS=$(aws acm describe-certificate \
    --certificate-arn "${EXISTING_CERT_ARN}" \
    --region us-east-1 \
    --query "Certificate.Status" \
    --output text)
  echo "Found existing certificate ${EXISTING_CERT_ARN} with status ${CERT_STATUS}"
  CERT_ARN="${EXISTING_CERT_ARN}"
else
  echo "Requesting new ACM certificate for ${SERVICE_DOMAIN} ..."
  CERT_ARN=$(aws acm request-certificate \
    --domain-name "${SERVICE_DOMAIN}" \
    --validation-method DNS \
    --region us-east-1 \
    --query CertificateArn \
    --output text)
  echo "Certificate requested: ${CERT_ARN}"
  CERT_STATUS="PENDING_VALIDATION"
fi

# Print CNAME validation record for manual addition to the DNS hosted zone
if [[ ${CERT_STATUS} == "PENDING_VALIDATION" ]]; then
  echo "Waiting for ACM to generate the DNS validation record..."
  sleep 10
  CNAME_NAME=$(aws acm describe-certificate \
    --certificate-arn "${CERT_ARN}" \
    --region us-east-1 \
    --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
    --output text 2> /dev/null || true)
  CNAME_VALUE=$(aws acm describe-certificate \
    --certificate-arn "${CERT_ARN}" \
    --region us-east-1 \
    --query "Certificate.DomainValidationOptions[0].ResourceRecord.Value" \
    --output text 2> /dev/null || true)

  echo ""
  echo "============================================================"
  echo "Add the following CNAME to the DNS hosted zone for ${SERVICE_DOMAIN}:"
  echo "  Name:  ${CNAME_NAME}"
  echo "  Value: ${CNAME_VALUE}"
  echo "Certificate ARN: ${CERT_ARN}"
  echo "============================================================"
fi

# Store certificate ARN in eu-west-2 SSM
echo "Storing certificate ARN in eu-west-2 SSM: /deploy/${ENVIRONMENT}/apex-certificate-arn"
aws ssm put-parameter \
  --name "/deploy/${ENVIRONMENT}/apex-certificate-arn" \
  --value "${CERT_ARN}" \
  --type String \
  --overwrite \
  --region eu-west-2

# Reset region
export AWS_REGION="eu-west-2"
