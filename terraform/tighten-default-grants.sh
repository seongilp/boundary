#!/usr/bin/env bash
# boundary dev 의 'Authenticated User Grants' 역할에서 target authorize-session 권한만 회수.
# Terraform null_resource 에서 호출됨.  인자: <addr> <auth_method_id> <login> <password>
set -euo pipefail
ADDR="$1"; AMID="$2"; LOGIN="$3"; PW="$4"
export BOUNDARY_ADDR="$ADDR"
export BOUNDARY_TOKEN="$(BDAY_PW="$PW" boundary authenticate password \
  -auth-method-id="$AMID" -login-name="$LOGIN" -password=env://BDAY_PW \
  -keyring-type=none -format=json | jq -r '.item.attributes.token // .item.token')"

RID="$(boundary roles list -scope-id=global -token=env://BOUNDARY_TOKEN -format=json \
  | jq -r '.items[]|select(.name=="Authenticated User Grants")|.id')"
[ -z "$RID" ] && { echo "기본 역할 못 찾음 — 건너뜀"; exit 0; }

ARGS=()
while IFS= read -r g; do
  [ -z "$g" ] && continue
  if printf '%s' "$g" | grep -q 'type=target'; then
    ARGS+=(-grant="ids=*;type=target;actions=list,read")
  else
    ARGS+=(-grant="$g")
  fi
done < <(boundary roles read -id="$RID" -token=env://BOUNDARY_TOKEN -format=json | jq -r '.item.grant_strings[]')

boundary roles set-grants -id="$RID" "${ARGS[@]}" -token=env://BOUNDARY_TOKEN >/dev/null
echo "기본 역할 보정 완료: $RID (target authorize-session 회수)"
