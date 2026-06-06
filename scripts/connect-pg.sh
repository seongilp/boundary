#!/usr/bin/env bash
# PostgreSQL 접속. Boundary 가 자격증명을 brokering 하므로 사용자는 비번을 모름.
#   사용법: ./scripts/connect-pg.sh [carol|bob] [static|dynamic]
#     static  = 고정 자격증명 brokering (pg-target)
#     dynamic = Vault 동적 자격증명 (pg-dyn-target)   ← 기본
# 로컬 psql 이 없어 도커 psql 로 붙는다.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

WHO="${1:-carol}"
MODE="${2:-dynamic}"
case "$MODE" in
  static)  TID="$(tf_out pg_target_id)" ;;
  dynamic) TID="$(tf_out pg_dyn_target_id)" ;;
  *) echo "MODE 는 static 또는 dynamic"; exit 1 ;;
esac
LP=15460

echo "==> '$WHO' 로 세션 열기 ($MODE 자격증명)"
export BOUNDARY_TOKEN="$(bday_token "$WHO")"
boundary connect -target-id="$TID" -listen-port="$LP" \
  -token=env://BOUNDARY_TOKEN -format=json > /tmp/bday_conn.json 2>&1 &
CPID=$!
trap 'kill $CPID 2>/dev/null || true' EXIT

OPENED=""
for i in $(seq 1 15); do
  kill -0 "$CPID" 2>/dev/null || break
  lsof -nP -iTCP:"$LP" -sTCP:LISTEN >/dev/null 2>&1 && { OPENED=1; break; }
  sleep 1
done
if [ -z "$OPENED" ]; then
  echo "⛔ DENIED — '$WHO' 는 접속 권한이 없습니다."
  exit 0
fi

DU="$(jq -r '.credentials[0].credential.username' /tmp/bday_conn.json)"
DP="$(jq -r '.credentials[0].credential.password' /tmp/bday_conn.json)"
echo "✅ 세션 열림. Boundary 가 내려준 계정: $DU  (사용자는 비번 모름)"
docker run --rm -e PGPASSWORD="$DP" postgres:16 \
  psql -h host.docker.internal -p "$LP" -U "$DU" -d "$PG_DB" \
       -c "select current_user as 접속계정, '$MODE 자격증명' as 방식, now();"
