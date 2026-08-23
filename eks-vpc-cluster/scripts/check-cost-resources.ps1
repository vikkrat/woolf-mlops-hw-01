param(
    [string]$Region = "eu-central-1",
    [string]$ClusterName = "mlops-hw2"
)

$ErrorActionPreference = "Continue"

Write-Host "=== EKS cluster ==="
aws eks describe-cluster --region $Region --name $ClusterName `
    --query 'cluster.{name:name,status:status}' --output table

Write-Host "=== EC2 instances tagged for this homework ==="
aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Homework,Values=2" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
    --query 'Reservations[].Instances[].{id:InstanceId,state:State.Name,type:InstanceType}' --output table

Write-Host "=== NAT Gateways tagged for this homework ==="
aws ec2 describe-nat-gateways --region $Region `
    --filter "Name=tag:Homework,Values=2" "Name=state,Values=pending,available,deleting" `
    --query 'NatGateways[].{id:NatGatewayId,state:State,vpc:VpcId}' --output table

Write-Host "=== Elastic IP allocations tagged for this homework ==="
aws ec2 describe-addresses --region $Region `
    --filters "Name=tag:Homework,Values=2" `
    --query 'Addresses[].{allocation:AllocationId,public_ip:PublicIp}' --output table

Write-Host "Empty tables / ResourceNotFoundException after destroy are expected."

