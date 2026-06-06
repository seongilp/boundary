#!/usr/bin/env bash
# 범용 접속: 임의의 target 에 로컬 프록시 포트를 연다 (SSH/DB 외 모든 TCP).
#   사용법: ./scripts/connect-tcp.sh <user> <target-name> <local-port>
#   예:    ./scripts/connect-tcp.sh carol redis-target 16379
#          (다른 터미널에서) redis-cli -p 16379 ping
# 포그라운드로 떠 있다가 Ctrl-C 로 종료.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

WHO="${1:?user 필요}"; TNAME="${2:?target-name 필요}"; LP="${3:?local-port 필요}"

export AT="$(bday_token "$ADMIN_LOGIN" "$ADMIN_PASS")"
TID="$(boundary targets list -recursive -token=env://AT -format=json \
  | jq -r --arg n "$TNAME" '.items[]|select(.name==$n)|.id')"
[ -z "$TID" ] && { echo "target '$TNAME' 못 찾음"; exit 1; }

export BOUNDARY_TOKEN="$(bday_token "$WHO")"
echo "==> '$WHO' 로 '$TNAME'($TID) → 로컬 127.0.0.1:$LP 프록시 (Ctrl-C 종료)"
exec boundary connect -target-id="$TID" -listen-port="$LP" -token=env://BOUNDARY_TOKEN
