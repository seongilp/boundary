#!/usr/bin/env bash
# lldap(LDAP)에 데모 사용자/그룹 시드. (회사 디렉터리 흉내)
#   그룹: sre, dba   사용자: dave(sre), erin(dba), frank(none)  비번: demo1234
set -euo pipefail
LLDAP_URL="${LLDAP_URL:-http://127.0.0.1:17170}"
LLDAP_ADMIN_PW="${LLDAP_ADMIN_PW:-adminpassword}"

TOK=$(curl -s -X POST "$LLDAP_URL/auth/simple/login" -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$LLDAP_ADMIN_PW\"}" | jq -r '.token')
[ -z "$TOK" ] || [ "$TOK" = "null" ] && { echo "lldap 로그인 실패"; exit 1; }
GQL() { curl -s -X POST "$LLDAP_URL/api/graphql" -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" -d "$1"; }

echo "==> 그룹 생성 (sre, dba)"
for g in sre dba; do
  GQL "{\"query\":\"mutation { createGroup(name: \\\"$g\\\") { id } }\"}" >/dev/null || true
done
GROUPS=$(GQL '{"query":"{ groups { id displayName } }"}')
gid() { echo "$GROUPS" | jq -r --arg n "$1" '.data.groups[]|select(.displayName==$n)|.id'; }

add_user() {
  local uid=$1 gid=$2
  GQL "{\"query\":\"mutation { createUser(user: {id: \\\"$uid\\\", email: \\\"$uid@example.com\\\", displayName: \\\"$uid (LDAP)\\\"}) { id } }\"}" >/dev/null || true
  [ -n "$gid" ] && GQL "{\"query\":\"mutation { addUserToGroup(userId: \\\"$uid\\\", groupId: $gid) { ok } }\"}" >/dev/null || true
  docker exec boundary-lldap /app/lldap_set_password --base-url http://localhost:17170 \
    --token "$TOK" --username "$uid" --password "demo1234" >/dev/null
  echo "   $uid 시드 완료"
}
echo "==> 사용자 생성 + 그룹 + 비번"
add_user dave "$(gid sre)"
add_user erin "$(gid dba)"
add_user frank ""

echo "✅ lldap 시드 완료. 웹UI: $LLDAP_URL (admin / $LLDAP_ADMIN_PW)"
