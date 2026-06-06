# SPIRE — 워크로드 zero-trust 신원 (SPIFFE)

"사람의 zero-trust 접근"은 Boundary가, **"서비스/워크로드의 zero-trust 신원"** 은 SPIRE가 담당.
워크로드가 비밀번호·시크릿 없이 **자동으로 암호학적 신분증(SVID, X.509 인증서)** 을 발급받는다.

## 구성 (kind-boundary-demo 클러스터)

```
SPIRE Server (statefulset)   ── 신원 발급, 등록 엔트리 관리
SPIRE Agent  (daemonset)     ── 노드에서 워크로드 attest + SVID 전달
Workload API (unix socket)   ── 워크로드가 SVID 받는 통로
```

## 핵심 개념

| 용어 | 뜻 |
|------|-----|
| **SPIFFE ID** | 워크로드 신원. `spiffe://example.org/ns/default/sa/default` |
| **SVID** | 그 신원의 증명서 (단기 X.509 인증서, 자동 rotate) |
| **Attestation** | "너 진짜 그 워크로드 맞아?" 검증 (k8s ns/sa/pod 등) |
| **Registration Entry** | 셀렉터(어떤 워크로드) → SPIFFE ID 매핑 |

## 실행 순서

```bash
# 1) 배포
kubectl --context kind-boundary-demo apply -f spire/quickstart/spire-namespace.yaml
kubectl --context kind-boundary-demo apply -f spire/quickstart/

# 2) 등록 엔트리 (노드 + 워크로드)
./spire/register-entries.sh

# 3) 워크로드가 SVID 받기
CLIENT=$(kubectl --context kind-boundary-demo get pod -l app=client -o jsonpath='{.items[0].metadata.name}')
kubectl --context kind-boundary-demo exec $CLIENT -- \
  /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock
```

## 주의 (이번에 겪은 것)
- 에이전트는 **k8s_psat** 어테스터 사용 → 노드 엔트리 셀렉터 접두사는 `k8s_psat:` (k8s_sat 아님)
- 노드 엔트리를 에이전트 기동 이후 만들면 에이전트 **재시작**(재attestation) 필요할 수 있음

## Boundary 와의 관계
- **Boundary** = 사람 → 리소스 (human-to-machine)
- **SPIRE** = 서비스 → 서비스 (machine-to-machine, mTLS)
- 둘 다 SPIFFE 신원 체계로 엮을 수 있음 (예: Vault가 SPIFFE 신원으로 워크로드에 시크릿 발급)
- 합치면 zero-trust 그림 완성: 사람도 서비스도 "신원 기반 + 단기 자격증명"
