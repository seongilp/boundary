#!/usr/bin/env python3
"""
암호화 API (POS용).
  - POS 단말을 mTLS 클라이언트 인증서로 '기기 인증' (CN = 매장/단말 식별자)
  - 암호화는 서버가 Vault Transit 으로 수행 → 키는 Vault 밖으로 안 나감
  - POS 는 평문↔암호문만 주고받음 (키를 절대 안 받음)
엔드포인트:  POST /encrypt {plaintext}  ·  POST /decrypt {ciphertext}
실행:  python3 server.py   (https://localhost:8443, mTLS 필수)
"""
import json, ssl, os, base64, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
CERTS = os.path.join(HERE, "certs")
VAULT_ADDR = "http://127.0.0.1:8200"
VAULT_TOKEN = open(os.path.join(HERE, ".vault_token")).read().strip()
KEY = "pos-data"
PORT = 8443


def vault(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{VAULT_ADDR}/v1/{path}",
        data=json.dumps(payload).encode(),
        headers={"X-Vault-Token": VAULT_TOKEN, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)


class H(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj, ensure_ascii=False).encode())

    def _device(self):
        # mTLS 클라이언트 인증서에서 기기 신원(CN) 추출
        cert = self.connection.getpeercert()
        for rdn in cert.get("subject", ()):
            for k, v in rdn:
                if k == "commonName":
                    return v
        return None

    def do_POST(self):
        device = self._device()  # mTLS 통과 못하면 여기 오지도 못함
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        try:
            if self.path == "/encrypt":
                pt = base64.b64encode(body["plaintext"].encode()).decode()
                ct = vault(f"transit/encrypt/{KEY}", {"plaintext": pt})["data"]["ciphertext"]
                print(f"[{device}] encrypt 요청 처리")
                self._json(200, {"device": device, "ciphertext": ct})
            elif self.path == "/decrypt":
                out = vault(f"transit/decrypt/{KEY}", {"ciphertext": body["ciphertext"]})
                pt = base64.b64decode(out["data"]["plaintext"]).decode()
                print(f"[{device}] decrypt 요청 처리")
                self._json(200, {"device": device, "plaintext": pt})
            else:
                self._json(404, {"error": "not found"})
        except Exception as e:
            self._json(500, {"error": str(e)})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(f"{CERTS}/server.crt", f"{CERTS}/server.key")
    ctx.load_verify_locations(f"{CERTS}/ca.crt")
    ctx.verify_mode = ssl.CERT_REQUIRED  # ★ 클라이언트 인증서 필수 (mTLS)
    httpd = HTTPServer(("127.0.0.1", PORT), H)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    print(f"암호화 API: https://localhost:{PORT} (mTLS 필수, 키는 Vault 안에만)")
    httpd.serve_forever()
