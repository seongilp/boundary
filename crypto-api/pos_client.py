#!/usr/bin/env python3
"""POS 단말 시뮬레이션 — 기기 인증서(mTLS)로 암호화 API 호출. 키는 절대 안 받음."""
import json, ssl, os, http.client

HERE = os.path.dirname(os.path.abspath(__file__))
CERTS = os.path.join(HERE, "certs")


def call(path, payload, with_cert=True):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.load_verify_locations(f"{CERTS}/ca.crt")
    ctx.check_hostname = False
    if with_cert:
        ctx.load_cert_chain(f"{CERTS}/pos.crt", f"{CERTS}/pos.key")  # ★ 기기 인증서
    conn = http.client.HTTPSConnection("localhost", 8443, context=ctx)
    conn.request("POST", path, json.dumps(payload), {"Content-Type": "application/json"})
    return json.load(conn.getresponse())


if __name__ == "__main__":
    print("=== POS(store3-pos7) → 암호화 API ===")
    enc = call("/encrypt", {"plaintext": "카드번호:4111-1111-1111-1111"})
    print(f"  기기인증: {enc['device']}")
    print(f"  암호문:   {enc['ciphertext'][:50]}...")
    dec = call("/decrypt", {"ciphertext": enc["ciphertext"]})
    print(f"  복호화:   {dec['plaintext']}")
    print("  → POS 는 키를 한 번도 안 받음 (서버가 Vault 로 암복호화)")
