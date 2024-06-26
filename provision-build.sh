#!/bin/bash
set -u

aws sso login --sso-session digital-identity

AWS_ACCOUNT=di-authentication-build
export AWS_ACCOUNT=$AWS_ACCOUNT
export AWS_PROFILE=$AWS_ACCOUNT
export AWS_PAGER=
export SKIP_AWS_AUTHENTICATION=true
export AUTO_APPLY_CHANGESET=true

./provisioner.sh $AWS_ACCOUNT aws-signer signer v1.0.8
./provisioner.sh $AWS_ACCOUNT container-signer container-signer v1.1.2
# ./provisioner.sh $AWS_ACCOUNT ecr-image-scan-findings-logger ecr-image-scan-findings-logger v1.2.0
./provisioner.sh $AWS_ACCOUNT github-identity github-identity v1.1.1

# ./provisioner.sh $AWS_ACCOUNT alerting-integration alerting-integration v1.0.6
# ./provisioner.sh $AWS_ACCOUNT api-gateway-logs api-gateway-logs v1.0.5
# ./provisioner.sh $AWS_ACCOUNT build-notifications build-notifications v2.3.1
# ./provisioner.sh $AWS_ACCOUNT certificate-expiry certificate-expiry v1.1.1
# ./provisioner.sh $AWS_ACCOUNT checkov-hook checkov-hook LATEST
# ./provisioner.sh $AWS_ACCOUNT infra-audit-hook infrastructure-audit-hook LATEST
# ./provisioner.sh $AWS_ACCOUNT lambda-audit-hook lambda-audit-hook LATEST
./provisioner.sh $AWS_ACCOUNT vpc vpc v2.5.1

./provisioner.sh $AWS_ACCOUNT frontend-pipeline sam-deploy-pipeline v2.58.1