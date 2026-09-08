#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${PROJECT_DIR}/terraform"

if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
  echo "Refusing destroy: terraform.tfvars not found in ${TF_DIR}" >&2
  exit 1
fi

terraform -chdir="$TF_DIR" plan -destroy -out=destroy.tfplan
echo "Review the plan above. Type the exact project name viktoriia-mlops-final to continue:"
read -r confirmation
[[ "$confirmation" == "viktoriia-mlops-final" ]] || { echo "Cancelled"; exit 2; }
terraform -chdir="$TF_DIR" apply destroy.tfplan
"${PROJECT_DIR}/scripts/aws-cost-audit.sh"
