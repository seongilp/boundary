#!/usr/bin/env bash
# SPIRE 등록 엔트리 생성 (kind-boundary-demo 클러스터).
#   ① 노드 alias: k8s_psat 으로 attest 한 에이전트 → 안정적 parent ID
#   ② 워크로드:  default/default SA → SPIFFE ID
# 주의: 에이전트는 k8s_psat 어테스터 사용 → 셀렉터 접두사 k8s_psat
set -euo pipefail
CTX="${CTX:-kind-boundary-demo}"
SS() { kubectl --context "$CTX" exec -n spire spire-server-0 -- /opt/spire/bin/spire-server "$@"; }

echo "==> 노드 alias 엔트리 (parent = 에이전트)"
SS entry create \
  -spiffeID spiffe://example.org/ns/spire/sa/spire-agent \
  -selector k8s_psat:cluster:demo-cluster \
  -selector k8s_psat:agent_ns:spire \
  -selector k8s_psat:agent_sa:spire-agent \
  -node 2>&1 | grep -iE "Entry ID|already" | head -1 || true

echo "==> 워크로드 엔트리 (default ns / default SA)"
SS entry create \
  -spiffeID spiffe://example.org/ns/default/sa/default \
  -parentID spiffe://example.org/ns/spire/sa/spire-agent \
  -selector k8s:ns:default \
  -selector k8s:sa:default 2>&1 | grep -iE "Entry ID|already" | head -1 || true

echo "==> 등록 엔트리 목록"
SS entry show 2>&1 | grep -iE "SPIFFE ID" | sed 's/^/   /'
echo
echo "✅ 완료. 워크로드 SVID 확인:"
echo "   CLIENT=\$(kubectl --context $CTX get pod -l app=client -o jsonpath='{.items[0].metadata.name}')"
echo "   kubectl --context $CTX exec \$CLIENT -- /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock"
