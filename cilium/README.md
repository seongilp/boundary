# Cilium + Hubble — 서비스 네트워크 통제 & 관측 (eBPF)

eBPF 기반 k8s 네트워킹/보안/관측. **서비스 간 통신을 정책으로 막고, 트래픽을 실시간 지도로** 본다.
zero-trust 그림에서 "서비스 ↔ 서비스 네트워크" 층 (사람=Boundary, 신원=SPIRE, 네트워크=Cilium).

## 전용 클러스터가 필요한 이유
Cilium 은 **CNI(네트워크 플러그인)** 라, 기존 클러스터에 얹으려면 CNI 교체(롤링 마이그레이션)가 필요하다.
데모는 기본 CNI 를 끈 **새 kind 클러스터**에서 한다. (운영 클러스터에 즉흥 설치 금지)

## 실행
```bash
# 1) CNI 없는 kind 클러스터
kind create cluster --name cilium-demo --config cilium/kind-cilium.yaml

# 2) Cilium + Hubble UI
cilium install --context kind-cilium-demo
cilium hubble enable --ui --context kind-cilium-demo
cilium status --context kind-cilium-demo --wait

# 3) 데모 앱 (Star Wars: deathstar / tiefighter / xwing)
kubectl --context kind-cilium-demo apply -f cilium/http-sw-app.yaml

# 4) 트래픽 생성
kubectl --context kind-cilium-demo exec tiefighter -- \
  curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing   # Ship landed

# 5) Hubble UI (트래픽 지도)
kubectl --context kind-cilium-demo -n kube-system port-forward svc/hubble-ui 12000:80 &
open http://127.0.0.1:12000/?namespace=default

# 6) 네트워크 정책 (org=empire 만 deathstar 허용)
kubectl --context kind-cilium-demo apply -f cilium/sw_l3_l4_policy.yaml
```

## 검증한 것
- **트래픽 지도**: Hubble UI 에서 tiefighter/xwing → deathstar 흐름이 그래프로 보임
- **정책 차단**: 정책 적용 후
  - tiefighter(제국) → `forwarded` (초록) ✅ "Ship landed"
  - xwing(반란군)   → `dropped` (빨강) ⛔ 타임아웃

## 정리
```bash
kind delete cluster --name cilium-demo
```

## Cilium 이 하는 일
| 영역 | 내용 |
|------|------|
| 네트워킹(CNI) | eBPF 기반 파드 네트워크 (iptables 대체) |
| 보안 | L3/L4 + **L7(HTTP)** 네트워크 정책 |
| 관측(Hubble) | 파드 간 트래픽 실시간 시각화 |
| (Tetragon) | eBPF 런타임 보안 관측 |
