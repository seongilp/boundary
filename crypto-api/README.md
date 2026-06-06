# POS 암호화 API — 기기 mTLS 인증 + 서버측 암호화

매장 POS 단말이 카드/민감 데이터를 암호화해야 할 때의 정답 아키텍처.
**키를 단말에 주지 않고**, 서버가 Vault Transit 으로 암복호화한다.

## 설계 원칙
1. **기기 인증 = mTLS 클라이언트 인증서** (단말별 고유, CN=매장/단말 식별자)
   - 발급은 **Vault PKI** 로 자동 (3000대면 등록 때 API 3000번, 폐기는 serial 로 1대만)
2. **암호화는 서버가 수행** — Vault Transit. 키는 Vault 밖으로 안 나감 (`exportable=false`)
3. **API 는 최소권한** Vault 토큰 (pos-data encrypt/decrypt 만, export/read 불가)
4. POS 는 **평문↔암호문만** 주고받음, 키를 절대 안 받음

## 흐름
```
POS 단말 ── mTLS(기기 인증서) ──> 암호화 API ── X-Vault-Token ──> Vault Transit
  평문/암호문만                    (CN으로 기기식별)              키는 여기 안에만
```

## 실행
```bash
# Vault (transit + pki) 기동 — setup.sh 참고
docker run -d --name crypto-vault --cap-add=IPC_LOCK -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=root hashicorp/vault:latest

# (setup) transit 키 + 최소권한 토큰 + 기기 인증서 발급  → setup.sh
./crypto-api/setup.sh

# API 서버 (mTLS 필수)
python3 crypto-api/server.py &

# POS 클라이언트 (기기 인증서로 암복호화)
python3 crypto-api/pos_client.py
```

## 검증
- ✅ POS(기기 인증서) → encrypt/decrypt 성공, 원문 복원
- ⛔ 인증서 없이 호출 → mTLS 거부 (`certificate required`)
- 🔒 키 export 시도 → 400 거부 (키는 Vault 밖으로 못 나감)

## 규모 (3000 단말)
- 인증서: **단말별 1개** (Vault PKI 자동 발급, 단기+자동회전)
- 유출 시: 해당 serial **1대만 폐기** (`vault write pki/revoke serial_number=...`)

## ⚠️ 카드 데이터면 PCI-DSS
- 키는 HSM 백킹(Vault Enterprise HSM) 권장, P2PE 고려, 전 과정 감사
