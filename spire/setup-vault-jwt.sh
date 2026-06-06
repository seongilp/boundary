#!/usr/bin/env bash
# SPIRE ↔ Vault 통합: 워크로드가 JWT-SVID(SPIFFE 신원)로 Vault 에 인증 → 동적 DB 자격증명.
#   1) SPIRE 번들의 JWT 서명키를 PEM 으로 추출
#   2) Vault JWT auth 에 등록 (SPIFFE ID → spire-db 정책)
#   3) 워크로드 JWT-SVID 로 로그인 → database/creds/boundary-role 발급
set -euo pipefail
CTX="${CTX:-kind-boundary-demo}"
V() { docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root boundary-vault vault "$@"; }

echo "==> ① SPIRE JWT 서명키 → PEM"
kubectl --context "$CTX" exec -n spire spire-server-0 -- \
  /opt/spire/bin/spire-server bundle show -format spiffe > /tmp/spire_bundle.json
python3 - <<'PY'
import json, base64
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
b=json.load(open('/tmp/spire_bundle.json'))
def u(s): return base64.urlsafe_b64decode(s+'='*(-len(s)%4))
k=[x for x in b['keys'] if 'x5c' not in x][0]   # jwt-svid 키
if k['kty']=='RSA':
    pub=rsa.RSAPublicNumbers(int.from_bytes(u(k['e']),'big'),int.from_bytes(u(k['n']),'big')).public_key()
else:
    crv={'P-256':ec.SECP256R1(),'P-384':ec.SECP384R1(),'P-521':ec.SECP521R1()}[k['crv']]
    pub=ec.EllipticCurvePublicNumbers(int.from_bytes(u(k['x']),'big'),int.from_bytes(u(k['y']),'big'),crv).public_key()
open('/tmp/spire_jwt_pub.pem','w').write(pub.public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo).decode())
PY
docker cp /tmp/spire_jwt_pub.pem boundary-vault:/tmp/spire_jwt_pub.pem >/dev/null

echo "==> ② Vault JWT auth + 정책 + 롤"
V auth enable jwt 2>/dev/null || true
V write auth/jwt/config jwt_validation_pubkeys=@/tmp/spire_jwt_pub.pem >/dev/null
docker exec -i -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root boundary-vault sh -c \
  'printf "path \"database/creds/boundary-role\" { capabilities = [\"read\"] }\n" > /tmp/spire-db.hcl; vault policy write spire-db /tmp/spire-db.hcl' >/dev/null
V write auth/jwt/role/spire-workload role_type=jwt user_claim=sub \
  bound_audiences=vault \
  bound_subject=spiffe://example.org/ns/default/sa/default \
  token_policies=spire-db token_ttl=5m >/dev/null

echo "==> ③ 워크로드 JWT-SVID 로 Vault 로그인 → 동적 DB 비번"
CLIENT=$(kubectl --context "$CTX" get pod -l app=client -o jsonpath='{.items[0].metadata.name}')
kubectl --context "$CTX" exec "$CLIENT" -- /opt/spire/bin/spire-agent api fetch jwt -audience vault \
  -socketPath /run/spire/sockets/agent.sock 2>/dev/null | sed -n '2p' | tr -d '[:space:]' \
  | docker exec -i boundary-vault sh -c 'cat > /tmp/svid.jwt'
VTOKEN=$(V write -field=token auth/jwt/login role=spire-workload jwt=@/tmp/svid.jwt)
echo "   Vault 토큰 발급됨 (SPIFFE 신원 검증 통과)"
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$VTOKEN" boundary-vault \
  vault read database/creds/boundary-role | grep -iE "username|password|lease_duration"
echo "✅ 워크로드가 시크릿 없이 SPIFFE 신원만으로 동적 DB 자격증명 획득"
