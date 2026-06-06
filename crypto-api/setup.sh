#!/usr/bin/env bash
# Vault transit(암호화) + pki(기기 인증서) + 최소권한 토큰 + 데모 인증서 셋업.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V() { docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root crypto-vault vault "$@"; }

echo "==> transit 엔진 + 키(pos-data)"
V secrets enable transit 2>/dev/null || true
V write -f transit/keys/pos-data >/dev/null

echo "==> API 최소권한 토큰 (encrypt/decrypt 만)"
docker exec -i -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root crypto-vault sh -c '
cat > /tmp/pos.hcl <<EOF
path "transit/encrypt/pos-data" { capabilities = ["update"] }
path "transit/decrypt/pos-data" { capabilities = ["update"] }
EOF
vault policy write pos-crypto /tmp/pos.hcl >/dev/null
vault token create -policy=pos-crypto -period=24h -field=token' > "$HERE/.vault_token"

echo "==> PKI 엔진 (기기 인증서 자동 발급기)"
V secrets enable pki 2>/dev/null || true
V secrets tune -max-lease-ttl=8760h pki >/dev/null
V write -field=certificate pki/root/generate/internal common_name="POS-Device-CA" ttl=8760h >/dev/null 2>&1 || true
V write pki/roles/pos-device allow_any_name=true max_ttl=24h key_type=rsa key_bits=2048 >/dev/null

echo "==> 데모용 mTLS 인증서 (CA + 서버 + POS 단말)"
mkdir -p "$HERE/certs"; cd "$HERE/certs"; O=/usr/bin/openssl
[ -f ca.crt ] || $O req -x509 -newkey rsa:2048 -nodes -days 365 -keyout ca.key -out ca.crt -subj "/CN=POS-Device-CA" 2>/dev/null
$O req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=localhost" 2>/dev/null
$O x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out server.crt 2>/dev/null
$O req -newkey rsa:2048 -nodes -keyout pos.key -out pos.csr -subj "/CN=store3-pos7" 2>/dev/null
$O x509 -req -in pos.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 365 -out pos.crt 2>/dev/null
echo "✅ 셋업 완료. python3 crypto-api/server.py 로 API 시작"
