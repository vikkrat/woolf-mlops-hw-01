#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-eu-north-1}"
PREFIX="${PROJECT_NAME:-viktoriia-mlops-final}"

echo "AWS zero-resource audit: region=${REGION}, prefix=${PREFIX}"
aws eks list-clusters --region "$REGION" --query "clusters[?contains(@, \`${PREFIX}\`)]"
aws ec2 describe-instances --region "$REGION" \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[].Instances[?Tags[?Key=='Project' && Value=='${PREFIX}']].[InstanceId,State.Name]"
aws ec2 describe-nat-gateways --region "$REGION" \
  --filter Name=tag:Project,Values="$PREFIX" Name=state,Values=pending,available,deleting \
  --query 'NatGateways[].[NatGatewayId,State]'
aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, \`${PREFIX}\`)].[LoadBalancerName,State.Code]"
aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[?contains(DBInstanceIdentifier, \`${PREFIX}\`)].DBInstanceIdentifier"
aws sfn list-state-machines --region "$REGION" \
  --query "stateMachines[?contains(name, \`${PREFIX}\`)].name"
aws lambda list-functions --region "$REGION" \
  --query "Functions[?contains(FunctionName, \`${PREFIX}\`)].FunctionName"
aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?contains(repositoryName, \`${PREFIX}\`)].repositoryName" 2>/dev/null || true
aws s3api list-buckets --query "Buckets[?contains(Name, \`${PREFIX}\`)].Name"
