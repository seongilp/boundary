# HashiCorp Boundary 도입 검토 — 개요 & PoC 결과

> 대상 독자: **임원/의사결정자**(1~3장) + **개발자/엔지니어**(4장 이후)
> 이 문서는 로컬 PoC(개념검증)로 실제 동작을 확인한 결과를 포함한다.

---

# Part 1. 임원용 요약 (Executive Summary)

## 1. 한 문장 정의

> **Boundary 는 "누가 어떤 서버·DB·시스템에 접근할 수 있는지"를 신원 기반으로 통제하고,
> 모든 접근을 기록하는 보안 접속 관문이다.**

직원은 더 이상 서버 IP·비밀번호·VPN·점프호스트(bastion)를 직접 다루지 않는다.
회사 계정으로 로그인하면, 허가된 리소스에만, 허가된 시간 동안 접속할 수 있다.

## 2. 지금 우리가 겪는 문제 (Boundary 가 푸는 것)

| 현재 방식의 문제 | 위험 | Boundary 해결 |
|------------------|------|---------------|
| 서버·DB 비밀번호를 팀이 **공유** (위키·슬랙·코드에 박힘) | 한 번 유출되면 영구 침해, 퇴사자도 접근 | 비번을 사람이 안 다룸 (자동 발급·폐기) |
| VPN/bastion 으로 **넓은 망 접근** 허용 | 한 명 뚫리면 내부망 전체 노출 | 리소스 단위 최소 권한 |
| **누가 무엇에 접근했는지 기록 없음** | 사고 조사 불가, 컴플라이언스 미달 | 모든 접근이 신원에 기록 |
| 권한 회수가 느림 (비번 변경·재배포) | 퇴사·사고 시 대응 지연 | 즉시 차단(revoke) |
| kubeconfig·SSH 키가 **노트북마다 흩뿌려짐** | 노트북 분실 = 클러스터 침해 | 중앙 통제, 단기 자격증명 |

## 3. 도입 시 얻는 것 (비즈니스 가치)

- **침해 반경 축소**: 공유 비밀번호 제거 → "비번 한 줄 유출 = 전체 침해" 시나리오 차단.
- **감사·컴플라이언스**: 접근 이력 기록(누가/언제/무엇). ISMS·SOC2·ISO27001 대응에 직접 기여.
- **빠른 사고 대응**: 의심 계정/세션을 즉시 차단.
- **운영 단순화**: 입·퇴사 시 권한 부여/회수를 코드로 관리(GitOps).
- **멀티클라우드 독립**: AWS·GCP·온프렘·k8s 어디든 단일 접근제어 평면.

### 대안과 비교 (요약)
| | AWS SSM | **Boundary** |
|---|---|---|
| 범위 | AWS EC2 중심 | 멀티클라우드·온프렘·DB·k8s 등 전방위 |
| 세션 녹화 | 기본 제공(무료) | Enterprise/HCP |
| 동적 자격증명 | 별도 조합 | Vault 연동 1급 지원 |
| 비용 | AWS 포함(저렴) | OSS 무료 / Enterprise·HCP 유료 |

> AWS 단일 환경이면 SSM 이 가성비 좋고, **멀티환경·DB·k8s·동적자격증명** 중심이면 Boundary 가 유리. 병행도 가능.

## 4. 도입 로드맵 (제안)

1. **PoC (완료)** — 로컬에서 SSH·DB·Redis·웹 접근제어 + 동적 자격증명 검증. (본 문서 Part 2)
2. **파일럿** — 1개 팀 + 비프로덕션 리소스에 적용, SSO(OIDC) 연동.
3. **확장** — 프로덕션 DB·k8s API 우선 적용 (침해 반경 가장 큰 곳).
4. **Enterprise 검토** — 세션 녹화·감사 요건이 있으면 HCP/Enterprise 전환.

---

# Part 2. PoC 결과 (무엇을 검증했나)

로컬에서 Docker + `boundary dev` + `vault` + Terraform 으로 실제 동작을 확인했다.

## 검증된 접근제어 매트릭스

| 사용자 | SSH | PostgreSQL(정적) | PostgreSQL(동적) | Redis | 웹앱 | k8s API |
|--------|-----|------------------|------------------|-------|------|---------|
| **alice** (앱/웹/SRE) | ✅ | ⛔ | ⛔ | ⛔ | ✅ | ✅ |
| **carol** (DBA) | ⛔ | ✅ | ✅ | ✅ | ⛔ | ⛔ |
| **bob** (권한없음) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |

→ 리소스별·사용자별로 권한이 분리되어, 권한 없는 사용자는 **접속 포트 자체가 열리지 않음**을 확인.

## 검증된 핵심 기능
- ✅ 신원 기반 접근제어 (role/grant)
- ✅ 리소스 종류 무관 (SSH/DB/Redis/HTTP/**Kubernetes API** — TCP면 무엇이든; kind 클러스터로 kubectl 검증)
- ✅ Credential Brokering (서버/DB 비번을 사용자가 모른 채 접속)
- ✅ **Vault 동적 자격증명** (접속마다 임시 DB 계정 발급 → 자동 폐기)
- ✅ GitOps (Terraform 으로 접근제어 전체를 코드 선언)
- ⚠️ 세션 녹화 = Enterprise/HCP 전용 (OSS 는 세션 메타데이터 감사까지)

---

# Part 3. 개발자용 — 개념

## 5.1 신원은 2층이다 (가장 중요)

| 층 | 계정 | 누가 관리 |
|----|------|-----------|
| ① **Boundary 신원** | alice, carol, bob (회사계정) | Boundary / SSO |
| ② **타겟 안 계정** | devuser, appuser, v-token-… | 서버·DB / Vault |

`alice` 로 Boundary 에 로그인해도 서버엔 `devuser` 로 들어간다. **둘은 별개.**
"누가 접근했나(①)"와 "서버에서 누구로 동작하나(②)"가 분리되어 추적이 된다.

## 5.2 접근제어 3요소
```
role = 누가(principal) + 무엇에(target) + 어떤 행동(grant: authorize-session)
```

## 5.3 자격증명 관리 3단계
| 방식 | 동작 |
|------|------|
| 직접 입력 | 사용자가 비번 타이핑 |
| **Brokering** | Boundary 가 저장한 비번을 건네줌 (사용자는 비번 모름) |
| **Vault 동적** | 접속마다 임시계정 발급·자동폐기 (공유 비번 자체가 없음) |

## 5.4 동작 흐름
```
사용자 → ① Boundary 로그인(신원) → ② 권한검사(authorize-session)
       → ③ Boundary 워커가 로컬 포트 열고 대상까지 프록시 → 접속
권한 없으면 ②에서 차단 → 포트 자체가 안 열림
```

---

# Part 4. 개발자용 — 사용법

## 6.1 일상 사용 (외울 건 사실상 2개)
```bash
# 로그인 (가끔, 토큰은 재사용됨)
boundary authenticate password -auth-method-id=<id> -login-name=<나>

# 접속 (붙고 싶을 때마다)
boundary connect ssh   -target-id=<target>            # SSH
boundary connect       -target-id=<target> -listen-port=15432   # 그 외 → 로컬포트로 기존 클라이언트 사용
```

## 6.2 내가 접근 가능한 리소스 보기
```bash
boundary targets list -recursive
# Authorized Actions 에 authorize-session 이 있으면 → 접속 가능
```

## 6.3 GitOps — 접근제어는 코드로 (이 PoC 방식)
새 리소스/권한은 CLI 가 아니라 Terraform 에 선언 후 apply.
```hcl
resource "boundary_target" "redis" {
  name = "redis-target"; type = "tcp"
  scope_id = var.project_scope_id
  default_port = 6379; address = "127.0.0.1"
}
resource "boundary_role" "redis_connect" {
  name = "redis-connect"; scope_id = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings = ["ids=${boundary_target.redis.id};actions=authorize-session,read"]
  principal_ids = [boundary_user.this["carol"].id]
}
```
```bash
terraform apply   # 변경 이력이 git 에 남고, 리뷰/롤백 가능
```

## 6.4 지원 리소스 (TCP면 무엇이든)
SSH · PostgreSQL · MySQL · Redis · MongoDB · RDP · HTTP/웹 · **Kubernetes API** · gRPC · 사내 커스텀 앱 …

---

# Part 5. PoC 실행 방법 (재현)
```bash
./scripts/up.sh        # 컨테이너(ssh/pg/redis/web/vault) + boundary dev
./scripts/apply.sh     # Terraform 으로 접근제어 적용
./scripts/matrix.sh    # 접근 매트릭스 확인
./scripts/connect-ssh.sh                # alice SSH
./scripts/connect-pg.sh carol dynamic   # carol DB (Vault 동적)
./scripts/down.sh --destroy             # 정리
```

저장소: 사내 GitHub `seongilp/boundary` (private)

---

## 부록. 운영 전환 시 체크리스트
- [ ] `boundary dev` → 프로덕션 모드 (PostgreSQL 백엔드 + KMS)
- [ ] 로컬 사용자 → **OIDC/LDAP(SSO)** 연동, MFA
- [ ] 워커를 각 네트워크/클라우드에 배치 (대상까지 도달 경로)
- [ ] Vault 연동으로 동적 자격증명 확대 (DB·k8s)
- [ ] 세션 녹화 필요 시 HCP/Enterprise
- [ ] 직노출 포트 차단 → Boundary 경유만 허용
