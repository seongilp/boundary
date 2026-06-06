# Boundary 접근제어 실습 (GitOps)

HashiCorp **Boundary** 로 SSH·PostgreSQL 접근제어를 로컬에서 실습하는 프로젝트.
인프라는 **Docker**, 접근제어 리소스는 **Terraform** 으로 선언한다 (GitOps).
DB 자격증명은 **Vault** 로 동적 발급한다.

> 📖 자세한 사용법: [`docs/user-guide.md`](docs/user-guide.md) (HTML: `docs/user-guide.html`)

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

| 사용자 | SSH | PG(정적) | PG(동적) | Redis | 웹앱 |
|--------|-----|----------|----------|-------|------|
| alice | ✅ | ⛔ | ⛔ | ⛔ | ✅ |
| carol | ⛔ | ✅ | ✅ | ✅ | ⛔ |
| bob | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |

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
