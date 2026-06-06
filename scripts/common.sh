#!/usr/bin/env bash
# 공통 설정 + 헬퍼. 다른 스크립트에서 source 한다.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
TF_DIR="$ROOT/terraform"

export BOUNDARY_ADDR="${BOUNDARY_ADDR:-http://127.0.0.1:9200}"
export AUTH_METHOD_ID="ampw_1234567890"   # boundary dev 고정 ID
export ADMIN_LOGIN="admin"
export ADMIN_PASS="password"
export DEMO_PASS="demo1234"

# 컨테이너 로그인 계정 (docker-compose.yml 과 일치)
export SSH_USER="devuser"
export PG_DB="appdb"

# Terraform output 값 읽기:  tf_out ssh_target_id
tf_out() { (cd "$TF_DIR" && terraform output -raw "$1"); }

# 사용자 로그인 → 토큰 문자열 반환 (keyring 미사용)
bday_token() {
  local login="$1" password="${2:-$DEMO_PASS}"
  BDAY_PW="$password" boundary authenticate password \
    -auth-method-id="$AUTH_METHOD_ID" -login-name="$login" \
    -password=env://BDAY_PW -keyring-type=none -format=json \
    | jq -r '.item.attributes.token // .item.token'
}
