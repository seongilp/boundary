# Boundary 운영 가이드 (Runbook)

> 대상: 플랫폼/보안 운영자(관리자) + 접근이 필요한 모든 구성원(사용자)
> 전제: Boundary 가 구축되어 있고, 접근제어는 **GitOps(Terraform)** 로 관리한다.

이 문서는 "누가 어떻게 권한을 신청하고, 관리자가 어떻게 부여하고, 사용자가 어떻게 접속하는가"의 표준 절차다.

---

## 0. 역할(R&R)

| 역할 | 책임 |
|------|------|
| **사용자(Requester)** | 접근 권한 신청, 승인 후 접속 |
| **승인자(Approver)** | 팀 리드/리소스 오너 — 권한 신청 승인/반려 |
| **운영자(Admin)** | Terraform 으로 권한 반영(apply), 리소스/사용자 관리 |
| **보안(Security)** | 정책 수립, 정기 권한 검토(access review), 감사 |

---

## 1. 권한 신청 절차 (사용자)

> 원칙: **모든 접근 권한은 신청 → 승인 → 코드 반영(PR)** 을 거친다. 구두/임시 부여 금지.

### 1-1. 신청서에 담을 내용
| 항목 | 예시 |
|------|------|
| 신청자 | alice (사번/계정) |
| 대상 리소스 | `prod-postgres` (pg-target) |
| 접근 사유 | "결제 버그 조사 — 읽기 필요" |
| 필요 기간 | 2026-06-10 ~ 06-17 (영구/한시) |
| 권한 수준 | 접속(authorize-session) / 자격증명 방식(정적·동적) |
| 승인자 | 데이터팀 리드 |

### 1-2. 신청 채널 (택1, 회사 표준에 맞춤)
- **권장: GitHub PR** — `terraform/roles.tf` 에 본인 추가하는 PR 생성 → 승인자가 리뷰 승인
- 또는 Jira/Slack 워크플로 티켓 → 운영자가 PR 대행

> PR 방식이 GitOps 와 자연스럽게 맞물려 **신청=변경이력=승인근거** 가 한 번에 남는다.

---

## 2. 권한 부여 절차 (운영자)

### 2-1. 승인 확인
- 신청 PR 에 **승인자(리소스 오너) Approve** 가 있는지 확인.
- 최소권한 원칙 점검: 사유에 비해 과한 권한 아닌지(예: 읽기면 되는데 전체 권한?).

### 2-2. 코드 반영 (Terraform)
권한 = `role` 의 `principal_ids` 에 사용자 추가. 예) alice 를 `pg-connect` 에 추가:
```hcl
# terraform/roles.tf
resource "boundary_role" "pg_connect" {
  name            = "pg-connect"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = ["ids=${boundary_target.pg.id};actions=authorize-session,read"]
  principal_ids   = [
    boundary_user.this["carol"].id,
    boundary_user.this["alice"].id,   # ← 신청 반영
  ]
}
```
```bash
./scripts/apply.sh        # terraform apply (변경분만 적용)
```

### 2-3. 신규 사용자라면 먼저 계정 생성
```hcl
# terraform/accounts.tf 의 demo_users 목록에 추가 (또는 OIDC 라면 그룹 매핑)
locals { demo_users = ["alice", "carol", "bob", "dave"] }   # dave 추가
```
> 운영 환경에서는 보통 로컬 계정 대신 **OIDC(SSO) 그룹**을 principal 로 매핑한다.
> 이 경우 "그룹 가입"이 곧 권한 부여이며, 입·퇴사가 SSO 와 자동 연동된다.

### 2-4. 한시 권한(임시 접근)
- 종료일이 있으면 캘린더/이슈에 회수 일정 등록 → 만료일에 `principal_ids` 에서 제거 PR.
- (Enterprise) 시간제한 정책으로 자동 만료 가능.

---

## 3. 접속 방법 안내 (사용자)

### 3-0. 최초 1회 설정
```bash
export BOUNDARY_ADDR=https://boundary.회사도메인   # 셸 프로파일에 추가 권장
```

### 3-1. 로그인 (토큰 만료 시 가끔)
```bash
boundary authenticate            # OIDC면 브라우저로 SSO 로그인
# (로컬계정 PoC면)
boundary authenticate password -auth-method-id=<id> -login-name=<나>
```
→ 토큰은 OS 키링에 저장되어 재사용. 매번 로그인 불필요.

### 3-2. 내가 접근 가능한 리소스 확인
```bash
boundary targets list -recursive
# Authorized Actions 에 authorize-session 있으면 접속 가능
```

### 3-3. 접속
| 리소스 | 명령 |
|--------|------|
| SSH | `boundary connect ssh -target-id=<id>` |
| PostgreSQL | `boundary connect postgres -target-id=<id>` |
| 기타(Redis/웹/k8s 등) | `boundary connect -target-id=<id> -listen-port=<로컬포트>` 후 기존 클라이언트로 `127.0.0.1:<로컬포트>` 접속 |

예시:
```bash
# DB
boundary connect postgres -target-id=$T -- -d appdb
# Redis
boundary connect -target-id=$T -listen-port=16379 &   ;   redis-cli -p 16379
# k8s
boundary connect -target-id=$T -listen-port=36443 &   ;   kubectl --server https://127.0.0.1:36443 get pods
# 웹
boundary connect -target-id=$T -listen-port=18080 &   ;   open http://127.0.0.1:18080
```

> 자격증명(서버/DB 비번)은 **Boundary 가 brokering/Vault 동적발급** 하므로 사용자가 따로 몰라도 된다.

### 3-4. 접속 종료
- 대화형(`connect ssh`)은 `exit`.
- 백그라운드 프록시는 해당 프로세스 종료(Ctrl-C 또는 `kill`).

---

## 4. 권한 회수 절차

| 상황 | 조치 |
|------|------|
| 업무 종료/한시 만료 | `roles.tf` 의 `principal_ids` 에서 제거 → `apply` (PR) |
| 퇴사 | 사용자(account/user) 삭제 또는 SSO 그룹 탈퇴 → 모든 권한 자동 소멸 |
| 사고/긴급 | 즉시 차단: 세션 취소 + 권한 제거 |

```bash
# 긴급 세션 차단 (특정 사용자의 활성 세션 종료)
boundary sessions list -recursive
boundary sessions cancel -id=<session-id>
```

---

## 5. 정기 운영 업무

| 주기 | 업무 |
|------|------|
| 상시 | 권한 신청 PR 리뷰/승인/apply |
| 주간 | 활성 세션·이상 접근 점검 (`boundary sessions list`) |
| 분기 | **접근 권한 검토(Access Review)** — `roles.tf` 전수 점검, 미사용 권한 회수 |
| 분기 | 한시 권한 만료 정리 |
| 수시 | 신규 리소스 온보딩(target+role 선언), Vault 동적자격증명 확대 |

### 신규 리소스 온보딩 (운영자)
```hcl
# 1) terraform/targets.tf — 리소스 등록
resource "boundary_target" "new_svc" {
  name = "new-svc-target"; type = "tcp"
  scope_id = var.project_scope_id
  default_port = 1234; address = "10.0.0.5"
}
# 2) terraform/roles.tf — 누구에게 줄지
resource "boundary_role" "new_svc_connect" {
  name = "new-svc-connect"; scope_id = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings = ["ids=${boundary_target.new_svc.id};actions=authorize-session,read"]
  principal_ids = [boundary_user.this["alice"].id]
}
```
```bash
./scripts/apply.sh
```

---

## 6. 감사 / 컴플라이언스

- **접근 이력**: `boundary sessions list -recursive` (누가/언제/무엇).
- **변경 이력**: 모든 권한 변경이 Git PR 로 남음 (누가 승인했는지 포함).
- **세션 녹화(명령/화면)**: Enterprise/HCP 전용. 요건 있으면 전환 검토.
- **정기 리포트**: 분기 Access Review 결과를 보안팀에 제출.

---

## 7. 문제 해결 (FAQ)

| 증상 | 원인 / 조치 |
|------|-------------|
| `connect` 시 "Target ID was not passed in" | `-target-id` 값이 비었음. 실제 ID 확인 |
| 프록시 포트가 안 열림 / `authorize-session ... Forbidden` | 권한 없음 → 권한 신청 필요 |
| `targets list` 에 리소스가 안 보임 | 해당 리소스 read 권한도 없음 → 신청 |
| 토큰 만료 | `boundary authenticate` 재로그인 |
| TLS 인증서 오류(k8s/HTTPS) | 대상 인증서 SAN 확인, 필요 시 CA 지정 |

---

## 부록. 표준 신청 템플릿 (복사용)
```
[Boundary 접근 권한 신청]
- 신청자:
- 대상 리소스(target):
- 권한 수준: authorize-session (읽기/쓰기 구분 필요 시 명시)
- 사유:
- 필요 기간: (영구 / YYYY-MM-DD ~ YYYY-MM-DD)
- 승인자:
```
