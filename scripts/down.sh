#!/usr/bin/env bash
# 정리: (옵션 --destroy 면 terraform destroy) → boundary dev 종료 → 컨테이너 내림.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

if [ "${1:-}" = "--destroy" ]; then
  echo "==> terraform destroy"
  (cd "$TF_DIR" && terraform destroy -auto-approve) || true
fi

echo "==> boundary dev 종료"
[ -f "$ROOT/.boundary.pid" ] && { kill "$(cat "$ROOT/.boundary.pid")" 2>/dev/null || true; rm -f "$ROOT/.boundary.pid"; }
pkill -f "boundary dev" 2>/dev/null || true

echo "==> 컨테이너 내림"
docker compose -f "$ROOT/docker-compose.yml" down

echo "✅ 정리 완료."
