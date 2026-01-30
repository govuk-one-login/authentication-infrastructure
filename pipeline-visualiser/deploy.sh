#!/bin/bash

set -e

# Configuration
ENVIRONMENT=${1:-dev}
REGION=${2:-eu-west-2}
CODESTAR_CONNECTION_ARN=${3}
VPC_STACK_NAME=${4:-vpc}

if [ -z "$CODESTAR_CONNECTION_ARN" ]; then
  echo "Usage: $0 <environment> <region> <codestar-connection-arn> [vpc-stack-name]"
  echo "Example: $0 dev eu-west-2 arn:aws:codestar-connections:eu-west-2:123456789012:connection/abc123 vpc"
  exit 1
fi

INFRASTRUCTURE_STACK_NAME="${ENVIRONMENT}-pipeline-visualiser-infrastructure"
PIPELINE_STACK_NAME="${ENVIRONMENT}-pipeline-visualiser-pipeline"

echo "Deploying Pipeline Visualiser infrastructure for environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "CodeStar Connection ARN: $CODESTAR_CONNECTION_ARN"
echo "VPC Stack Name: $VPC_STACK_NAME"

# Deploy infrastructure stack
echo "Deploying infrastructure stack..."
aws cloudformation deploy \
  --template-file infrastructure.yaml \
  --stack-name "$INFRASTRUCTURE_STACK_NAME" \
  --parameter-overrides \
  Environment="$ENVIRONMENT" \
  VpcStackName="$VPC_STACK_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION"

echo "Infrastructure stack deployed successfully!"

# Wait for infrastructure stack to complete
echo "Waiting for infrastructure stack to complete..."
aws cloudformation wait stack-deploy-complete \
  --stack-name "$INFRASTRUCTURE_STACK_NAME" \
  --region "$REGION"

# Deploy pipeline stack
echo "Deploying pipeline stack..."
aws cloudformation deploy \
  --template-file deployment-pipeline.yaml \
  --stack-name "$PIPELINE_STACK_NAME" \
  --parameter-overrides \
  Environment="$ENVIRONMENT" \
  CodeStarConnectionArn="$CODESTAR_CONNECTION_ARN" \
  InfrastructureStackName="$INFRASTRUCTURE_STACK_NAME" \
  --capabilities CAPABILITY_IAM \
  --region "$REGION"

echo "Pipeline stack deployed successfully!"

# Get outputs
echo "Getting stack outputs..."
# shellcheck disable=SC2016
ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name "$INFRASTRUCTURE_STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)

# shellcheck disable=SC2016
ECR_URI=$(aws cloudformation describe-stacks \
  --stack-name "$INFRASTRUCTURE_STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
  --output text)

echo ""
echo "Deployment completed successfully!"
echo "Application Load Balancer DNS: $ALB_DNS"
echo "ECR Repository URI: $ECR_URI"
echo ""
echo "Next steps:"
echo "1. Push your code to trigger the pipeline"
echo "2. Access the application at: http://$ALB_DNS"
echo "3. Configure your domain name to point to the ALB if needed"
