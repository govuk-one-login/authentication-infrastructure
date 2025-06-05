#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1}"
OLD_ACCOUNT_PROFILE="${2}"
NEW_ACCOUNT_PROFILE="${3}"

if [ "$ENVIRONMENT" = "development" ]; then
  ENVIRONMENT="dev"
fi

export AWS_PROFILE=${OLD_ACCOUNT_PROFILE}
if ! aws sts get-caller-identity &> /dev/null; then
  aws sso login --profile "${AWS_PROFILE}"
fi
export AWS_REGION="eu-west-2"

case "${ENVIRONMENT}" in
  dev | build)
    interventions_api=$(aws apigateway get-rest-apis --query "items[?name=='${ENVIRONMENT}-di-interventions-api-stub'].[id]" --output text)
    ticf_cri_api=$(aws apigateway get-rest-apis --query "items[?name=='${ENVIRONMENT}-di-ticf-cri-stub'].[id]" --output text)
    ;;
  *)
    interventions_api=$(aws secretsmanager get-secret-value --secret-id "/deploy/${ENVIRONMENT}/account_intervention_service_uri" --query 'SecretString' --output text)
    ticf_cri_api=$(aws secretsmanager get-secret-value --secret-id "/deploy/${ENVIRONMENT}/ticf_cri_service_uri" --query 'SecretString' --output text)
    old_vpc_endpoint=$(aws ec2 describe-vpc-endpoints --filters 'Name=service-name,Values=com.amazonaws.eu-west-2.execute-api' --query 'VpcEndpoints[].VpcEndpointId' --output text)
    ;;
esac

export AWS_PROFILE=${NEW_ACCOUNT_PROFILE}
vpc_endpoint=$(aws ec2 describe-vpc-endpoints --filters 'Name=service-name,Values=com.amazonaws.eu-west-2.execute-api' --query 'VpcEndpoints[].VpcEndpointId' --output text)

case "${ENVIRONMENT}" in
  dev | build)
    account_intervention_service_uri="https://${interventions_api}-${vpc_endpoint}.execute-api.eu-west-2.amazonaws.com/${ENVIRONMENT}"
    ticf_cri_service_uri="https://${ticf_cri_api}-${vpc_endpoint}.execute-api.eu-west-2.amazonaws.com/${ENVIRONMENT}"
    ;;
  *)
    account_intervention_service_uri=${interventions_api/"$old_vpc_endpoint"/"$vpc_endpoint"}
    ticf_cri_service_uri=${ticf_cri_api/"$old_vpc_endpoint"/"$vpc_endpoint"}
    ;;
esac

aws secretsmanager create-secret --name "/deploy/${ENVIRONMENT}/account_intervention_service_uri" --secret-string "${account_intervention_service_uri}" --region "${AWS_REGION}"
aws secretsmanager create-secret --name "/deploy/${ENVIRONMENT}/ticf_cri_service_uri" --secret-string "${ticf_cri_service_uri}" --region "${AWS_REGION}"
