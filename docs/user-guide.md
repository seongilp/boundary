# Boundary 접근제어 실습 — 사용자 가이드

HashiCorp **Boundary** 로 SSH 서버와 PostgreSQL 에 대한 접근제어를 로컬에서
실습하는 GitOps 프로젝트. 인프라는 Docker, 접근제어 리소스는 Terraform 으로 선언한다.

---

## 1. 한눈에 보는 구조

```
   사용자(alice/carol/bob)
        │  ① Boundary 로그인 (신원)
        ▼
   ┌─────────────┐   ② authorize-session (권한검사)
   │  Boundary   │──────────────┐
   │ dev (9200)  │              │ ③ 세션 중개 (proxy)
   └─────┬───────┘              ▼
         │ ④ Vault 에 동적자격증명 요청   ┌──────────────┐
         ▼                              │ ssh-target   │ :2222
   ┌─────────────┐                      │ (devuser)    │
   │ Vault (8200)│                      ├──────────────┤
   │ 동적 DB계정  │─────────────────────▶│ pg-target    │ :5432
   └─────────────┘   임시계정 생성       │ (appuser/동적)│
                                         └──────────────┘
```

- **Boundary**: 누가 어떤 리소스에 접근 가능한지 통제 (role/grant). 직접 접속 차단, 프록시 경유.
- **Vault**: 접속할 때마다 임시 DB 계정을 발급 → TTL 만료 시 자동 폐기 (zero-standing-privilege).
- **Terraform**: 위 접근제어 규칙을 코드로 선언 (GitOps 단일 소스).

## 2. 사전 준비

| 도구 | 설치 |
|------|------|
| Docker | Docker Desktop |
| boundary CLI | `brew install hashicorp/tap/boundary` |
| terraform | `brew install hashicorp/tap/terraform` |
| jq | `brew install jq` |

## 3. 빠른 시작

```bash
# 1) 인프라 기동 (컨테이너 + boundary dev)
./scripts/up.sh

# 2) 접근제어 적용 (Terraform)
./scripts/apply.sh          # = terraform init + apply

# 3) 접근제어 매트릭스 확인
./scripts/matrix.sh

# 4) 실제 접속
./scripts/connect-ssh.sh                  # alice 로 SSH
./scripts/connect-pg.sh carol dynamic     # carol 로 DB (Vault 동적 자격증명)
./scripts/connect-pg.sh carol static      # carol 로 DB (고정 자격증명 brokering)

# 5) 정리
./scripts/down.sh           # 컨테이너+dev 종료 (--destroy 추가 시 terraform destroy)
```

## 4. 접근 매트릭스

| 사용자 | SSH | PG(정적) | PG(동적) | 역할 |
|--------|-----|----------|----------|------|
| **alice** | ✅ | ⛔ | ⛔ | SSH 담당 |
| **carol** | ⛔ | ✅ | ✅ | DBA |
| **bob** | ⛔ | ⛔ | ⛔ | 권한 없음 |

모든 사용자 비밀번호: `demo1234`

## 5. 핵심 개념

### 5.1 신원은 2층이다
| 층 | 계정 | 관리 주체 |
|----|------|-----------|
| ① Boundary 신원 | alice, carol, bob | Boundary (role/grant) |
| ② 타겟 안 계정 | devuser, appuser, v-token-… | 서버/DB (또는 Vault) |

`alice` 로 Boundary 에 로그인해도, SSH 서버엔 `devuser` 로 들어간다. 둘은 별개.

### 5.2 접근제어 3요소
```
role = 누가(principal) + 무엇에(target) + 어떤 행동(grant: authorize-session)
```
예) `ssh-connect` role = principal:alice + grant:`ids=<ssh-target>;actions=authorize-session`

### 5.3 Credential 관리 3단계
| 방식 | 동작 | 이 프로젝트 |
|------|------|-------------|
| 직접 입력 | 사용자가 비번 타이핑 | (기본) |
| **Brokering** | Boundary 가 저장한 비번을 건네줌 | pg-target(정적) |
| **Vault 동적** | 접속마다 임시계정 발급, 자동폐기 | pg-dyn-target |

## 6. 새 리소스 추가하기 (GitOps 방식)

CLI 로 만들지 말고 `terraform/` 에 선언 후 apply 한다.

```hcl
# terraform/targets.tf 에 추가
resource "boundary_target" "redis" {
  name         = "redis-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = 6379
  address      = "127.0.0.1"
}

# terraform/roles.tf 에 추가 (alice 에게 권한)
resource "boundary_role" "redis_connect" {
  name            = "redis-connect"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = ["ids=${boundary_target.redis.id};actions=authorize-session,read"]
  principal_ids   = [boundary_user.this["alice"].id]
}
```
```bash
./scripts/apply.sh
```

## 7. 웹 UI

| UI | 주소 | 로그인 |
|----|------|--------|
| Boundary Admin | http://127.0.0.1:9200 | admin / password |
| Vault | http://127.0.0.1:8200 | token: `root` |

Boundary UI 에서 타겟은 **project 스코프 안**(Orgs → org → Projects → project)에 있다.
세션은 Sessions 메뉴에서 실시간으로 보인다.

## 8. 자주 묻는 것

- **접속할 때마다 스크립트를 돌려야 하나?** 아니다. 로그인은 가끔(`boundary authenticate`),
  접속은 `boundary connect ssh -target-id=…` 만 반복. 토큰은 keyring 에 저장돼 재사용된다.
- **alice/bob 은 로컬 사용자인가?** 그렇다. Boundary password auth method 의 로컬 계정.
  실무에선 OIDC/LDAP(SSO)로 대체한다.
- **`postgres.boundary.dev` 같은 건 뭔가?** `boundary dev` 가 깔아둔 예제 alias(더미). 무시.

## 9. 파일 구조

```
boundary/
├── docker-compose.yml      # ssh / postgres / vault 컨테이너
├── terraform/              # 접근제어 선언 (GitOps 소스)
│   ├── accounts.tf         # 사용자
│   ├── targets.tf          # 리소스
│   ├── roles.tf            # 권한
│   ├── credentials.tf      # 자격증명 store/library
│   ├── vault.tf            # Vault 동적 자격증명 설정
│   └── ...
├── scripts/                # 운영 헬퍼 (up/apply/matrix/connect/down)
├── docs/                   # 이 가이드
└── web/                    # 접근제어 설명 다이어그램 페이지
```
