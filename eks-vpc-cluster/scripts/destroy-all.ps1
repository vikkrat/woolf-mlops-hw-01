param(
    [Parameter(Mandatory = $true)]
    [string]$StateBucket
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Destroying EKS and node groups first..."
Push-Location (Join-Path $ProjectRoot "eks")
try {
    terraform init -backend-config=backend.hcl
    terraform destroy -auto-approve -var="state_bucket=$StateBucket"
} finally {
    Pop-Location
}

Write-Host "Destroying VPC, NAT Gateway and Elastic IP second..."
Push-Location (Join-Path $ProjectRoot "vpc")
try {
    terraform init -backend-config=backend.hcl
    terraform destroy -auto-approve
} finally {
    Pop-Location
}

Write-Host "Terraform destroy completed. Run scripts/check-cost-resources.ps1 now."

