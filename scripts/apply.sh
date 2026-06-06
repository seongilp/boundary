#!/usr/bin/env bash
# Terraform 으로 Boundary/Vault 접근제어 리소스를 선언형으로 적용 (GitOps).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

cd "$TF_DIR"
[ -d .terraform ] || terraform init
terraform apply "$@"
echo
echo "✅ 적용 완료. 확인: ./scripts/matrix.sh"
