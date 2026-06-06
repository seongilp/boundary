#!/usr/bin/env bash
# 접근제어 매트릭스: 사용자 × 리소스 authorize-session 가능 여부.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

SSH_T="$(tf_out ssh_target_id)"
PG_T="$(tf_out pg_target_id)"
PGD_T="$(tf_out pg_dyn_target_id)"

chk() { boundary targets authorize-session -id="$1" -token=env://T >/dev/null 2>&1 && printf "  ✅  " || printf "  ⛔  "; }

printf "\n%-8s %-8s %-8s %-10s\n" "사용자" "SSH" "PG(정적)" "PG(동적)"
printf -- "--------------------------------------------\n"
for u in alice carol bob; do
  export T="$(bday_token "$u")"
  printf "%-8s" "$u"; chk "$SSH_T"; chk "$PG_T"; chk "$PGD_T"; printf "\n"
done
printf -- "--------------------------------------------\n"
echo "alice=SSH / carol=DB(정적·동적) / bob=권한없음"
