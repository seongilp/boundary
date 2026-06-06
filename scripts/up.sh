#!/usr/bin/env bash
# 인프라 기동: 컨테이너(SSH/PostgreSQL/Vault) + boundary dev 컨트롤러.
# 그 다음 scripts/apply.sh 로 Terraform 을 적용한다.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

echo "==> 1) 컨테이너 기동 (ssh-target, postgres-target, vault)"
docker compose -f "$ROOT/docker-compose.yml" up -d

echo "==> 2) postgres / vault 준비 대기"
for i in $(seq 1 30); do docker exec boundary-pg-target pg_isready -U appuser -d appdb >/dev/null 2>&1 && break; sleep 1; done
for i in $(seq 1 30); do docker exec boundary-vault sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault status' >/dev/null 2>&1 && break; sleep 1; done

echo "==> 3) boundary dev 컨트롤러 시작"
if pgrep -f "boundary dev" >/dev/null 2>&1; then
  echo "    이미 실행 중 — 건너뜀"
else
  nohup boundary dev -login-name="$ADMIN_LOGIN" -password="$ADMIN_PASS" \
    > "$ROOT/boundary-dev.log" 2>&1 &
  echo $! > "$ROOT/.boundary.pid"
fi
for i in $(seq 1 40); do bday_token "$ADMIN_LOGIN" "$ADMIN_PASS" >/dev/null 2>&1 && break; sleep 1; done

echo
echo "✅ 인프라 준비 완료."
echo "   - Boundary UI : $BOUNDARY_ADDR  (admin/password)"
echo "   - Vault UI    : http://127.0.0.1:8200  (token: root)"
echo "   다음: ./scripts/apply.sh   (Terraform 으로 접근제어 적용)"
