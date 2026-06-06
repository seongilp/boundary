# Boundary 접근제어 + Zero-Trust 인프라 실습

HashiCorp **Boundary** 접근제어에서 시작해, 인증(SSO)·신원·시크릿·서비스 보안까지
로컬(Docker + kind)로 직접 띄워보며 학습한 zero-trust 인프라 모음.

> 📖 핵심 문서: [개요/PoC](docs/boundary-overview.md) · [운영 가이드](docs/operations-runbook.md) · [아키텍처](docs/architecture.md) · [사용자 가이드](docs/user-guide.md) (각 `.html` 버전 있음)

## 전체 구성 (학습 여정)

| 모듈 | 역할 | 위치 |
|------|------|------|
| **Boundary** | 사람 → 서버/DB 접근제어 (RBAC, 세션 프록시) | `terraform/`, `scripts/` |
| **Vault** | 동적 DB 자격증명 (접속마다 임시계정) | `terraform/vault.tf` |
| **Keycloak** | OIDC SSO 로그인 + MFA + 토스풍 테마 | `terraform/oidc.tf`, `keycloak/` |
| **lldap** | LDAP 디렉터리 (사용자/그룹) → Keycloak federation | `keycloak/`, `scripts/seed-lldap.sh` |
| **웹 포털** | 접근권한 셀프서비스 신청 + 운영자 페이지 (미니 IGA) | `request-portal/` |
| **SPIRE** | 서비스 → 서비스 신원(SVID) + Vault연동 + mTLS | `spire/` |
| **Temporal** | durable 워크플로우 (결제 사가, 자동 재시도/재개) | `temporal/` |
| **Cilium+Hubble** | 서비스 네트워크 정책 + 트래픽 시각화 (eBPF) | `cilium/` |

```
사람   : lldap → Keycloak(SSO) → Boundary(RBAC) → 서버/DB/k8s
서비스 : SPIRE(SVID) → mTLS / Vault인증 → 동적 자격증명
네트워크: Cilium(정책) + Hubble(관측)
공통   : 신원 기반 · 단기 자격증명 · 시크릿 제로
```

---
## (핵심) Boundary 접근제어 — GitOps

## 구성

| 요소 | 내용 |
|------|------|
| Boundary | `boundary dev` (인메모리, `:9200`) — 접근제어 통제 |
| Vault | dev 모드 (`:8200`) — 동적 DB 자격증명 발급 |
| SSH 타겟 | Docker `openssh-server` (`:2222`) |
| PostgreSQL 타겟 | Docker `postgres:16` (`:5432`) |
| IaC | Terraform (`boundary` + `vault` provider) |

## 빠른 시작

```bash
./scripts/up.sh        # 컨테이너 + boundary dev 기동
./scripts/apply.sh     # Terraform 으로 접근제어 적용
./scripts/matrix.sh    # 접근 매트릭스 확인

./scripts/connect-ssh.sh                # alice 로 SSH
./scripts/connect-pg.sh carol dynamic   # carol 로 DB (Vault 동적 자격증명)

./scripts/down.sh      # 정리 (--destroy 로 terraform destroy 포함)
```

## 접근 매트릭스

| 사용자 | SSH | PG(정적) | PG(동적) | Redis | 웹앱 | k8s |
|--------|-----|----------|----------|-------|------|-----|
| alice | ✅ | ⛔ | ⛔ | ⛔ | ✅ | ✅ |
| carol | ⛔ | ✅ | ✅ | ✅ | ⛔ | ⛔ |
| bob | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |

비밀번호: 모두 `demo1234` · `./scripts/matrix.sh` 로 확인 (타겟 추가 시 자동 반영)

> SSH/DB뿐 아니라 **TCP면 무엇이든** 통제된다 (Redis·HTTP·RDP·k8s 등). 범용 접속: `./scripts/connect-tcp.sh <user> <target-name> <local-port>`

## 디렉터리

```
boundary/
├── docker-compose.yml   # ssh / postgres / vault 컨테이너
├── terraform/           # 접근제어 선언 (GitOps 단일 소스)
│   ├── accounts.tf      # 사용자(alice/carol/bob)
│   ├── targets.tf       # 리소스(target)
│   ├── roles.tf         # 권한(role/grant/principal)
│   ├── credentials.tf   # 자격증명 store/library
│   ├── vault.tf         # Vault 동적 자격증명
│   ├── providers.tf / variables.tf / outputs.tf / versions.tf
│   └── terraform.tfvars.example
├── scripts/             # 운영 헬퍼 (up/apply/matrix/connect/down)
├── docs/                # 사용자 가이드 (md + html)
└── web/                 # 접근제어 개념 다이어그램 페이지
```

## GitOps 흐름

접근제어 변경은 **`terraform/` 수정 → `./scripts/apply.sh`** 로만 한다.
새 리소스/권한도 `.tf` 에 선언한다 (가이드 6장 참고).

## 주의

- `boundary dev` / `vault` dev 모드는 재시작하면 상태가 사라진다. 재시작 후 `apply.sh` 다시 실행.
- dev 모드 토큰/비번은 학습 전용. 운영에선 OIDC/LDAP 인증 + KMS/Vault 시크릿으로 대체한다.
- 시크릿(`terraform.tfvars`)과 상태(`*.tfstate`)는 `.gitignore` 로 git 에서 제외된다.
