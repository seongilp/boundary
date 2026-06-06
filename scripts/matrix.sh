#!/usr/bin/env bash
# 접근제어 매트릭스: 사용자 × (우리가 관리하는) target authorize-session 가능 여부.
# 타겟 목록을 동적으로 읽어, 새 리소스를 추가해도 자동 반영된다.
# (boundary dev 가 자동 생성한 'Generated ...' 예제 타겟은 제외)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/common.sh"

# admin 으로 관리 대상 타겟(name,id) 수집 — 'Generated' 로 시작하는 더미는 제외
export AT="$(bday_token "$ADMIN_LOGIN" "$ADMIN_PASS")"
NAMES=(); IDS=()
while IFS=$'\t' read -r name id; do
  [ -z "$name" ] && continue
  NAMES+=("$name"); IDS+=("$id")
done < <(boundary targets list -recursive -token=env://AT -format=json \
  | jq -r '.items[] | select(.name|test("-target$")) | "\(.name)\t\(.id)"' | sort)

# 헤더
printf "\n%-8s" "사용자"
for n in "${NAMES[@]}"; do printf "%-15s" "$n"; done
printf "\n%s\n" "$(printf '%.0s-' $(seq 1 $((8 + 15*${#NAMES[@]}))))"

# 각 사용자별로, 그 사용자 토큰의 authorized_actions 에 authorize-session 있는지 확인
for u in alice carol bob; do
  export UT="$(bday_token "$u")"
  # 사용자가 보는 타겟별 authorized_actions 맵
  ACTS="$(boundary targets list -recursive -token=env://UT -format=json \
    | jq -r '.items[] | "\(.id)=\(.authorized_actions|join(","))"')"
  printf "%-8s" "$u"
  for id in "${IDS[@]}"; do
    line="$(printf '%s\n' "$ACTS" | grep "^$id=" || true)"
    if printf '%s' "$line" | grep -q "authorize-session"; then printf "%-15s" "  ✅"; else printf "%-15s" "  ⛔"; fi
  done
  printf "\n"
done
echo
echo "✅=접속가능  ⛔=차단   (alice=SSH·웹 / carol=DB·Redis / bob=권한없음)"
