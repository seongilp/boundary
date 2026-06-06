# Boundary 접근제어 — 최종 아키텍처

회사 신원(LDAP) → SSO(Keycloak) → 접근제어(Boundary) → 리소스 까지,
**인증·권한·자격증명·신청**을 모두 갖춘 zero-trust 원격접속 아키텍처. 전부 로컬 PoC로 검증됨.

---

## 1. 전체 그림

```
┌──────────────┐   사람·그룹 관리 (인사)
│   lldap      │   dave→sre, erin→dba, frank→none
│  (LDAP)      │   * 실무에선 AD / 회사 디렉터리
└──────┬───────┘
       │ ① User Federation (동기화 + 그룹 매퍼)
       ▼
┌──────────────┐   인증 + MFA + 로그인 테마
│  Keycloak    │   LDAP 사용자 import, groups claim 발급
│  (OIDC IdP)  │
└──────┬───────┘
       │ ② OIDC (auth-code)
       ▼
┌──────────────┐   "누가 무엇에 접근?" 통제
│  Boundary    │   managed group(sre/dba) + role/grant
│ (controller  │   세션 프록시 / 자격증명 brokering
│  + worker)   │
└──────┬───────┘
       │ ③ 세션 중개 (직접 접속 X)
       ▼
┌─────────────────────────────────────────────┐
│ SSH · PostgreSQL · Redis · 웹 · k8s API ...   │  ← 타겟
└─────────────────────────────────────────────┘
       ▲
       │ ④ 동적 자격증명 (접속마다 임시계정)
┌──────────────┐
│   Vault      │
└──────────────┘

[ GitOps ]  Terraform 이 Boundary/Vault 리소스를 선언 (access.json / targets.json)
[ 신청   ]  웹 포털 → PR → 승인 → apply   (미니 IGA)
```

## 2. 계층별 역할 (관심사 분리)

| 계층 | 컴포넌트 | 책임 | 관리 위치 |
|------|----------|------|-----------|
| **신원** | lldap / AD | 누가 존재하나 + 그룹 멤버십 | LDAP 웹UI (인사) |
| **인증** | Keycloak | 로그인·MFA·SSO, 그룹 claim | IdP 설정 (1회) |
| **권한** | Boundary | 그룹→리소스 정책, 세션 통제 | Terraform (GitOps) |
| **자격증명** | Vault / Cred Store | 서버·DB 비번 brokering·동적발급 | Terraform |
| **신청** | 웹 포털 | 셀프서비스 요청·승인 | git PR |

> 핵심 원칙: **신원(누구)·권한(무엇)·자격증명(비번)을 분리.** 각 계층이 독립적으로 교체 가능.

## 3. 데이터 흐름 (alice 가 SSH 접속)

```
1. alice → Boundary 에 "OIDC 로그인" 요청
2. Boundary → Keycloak 로 리다이렉트 → alice 로그인 (MFA)
   (Keycloak 은 alice 를 lldap 에서 federation)
3. Keycloak → 토큰 발급 (groups: ["sre"])
4. Boundary → managed group "sre" 에 편입 → ssh-target authorize 권한 확인
5. alice → boundary connect ssh → 워커가 SSH 서버로 프록시
   (자격증명은 Vault/brokering 으로 자동 주입, alice 는 비번 모름)
```

## 4. 권한 모델 (그룹 기반)

```
LDAP 그룹     Keycloak       Boundary managed group     Role (Terraform)
  sre     →   groups:sre  →       sre              →    ssh/web/k8s
  dba     →   groups:dba  →       dba              →    pg/pg-dyn/redis
```
- **개인을 매핑하지 않음.** "어느 그룹이냐"로 권한 결정.
- 신규 입사자 = LDAP 그룹에 추가하면 끝 (Boundary 무수정).
- 검증: lldap 에서 dave 를 dba 에 넣자 → groups `[sre]`→`[dba,sre]` → Boundary 권한 자동 확장.

## 5. 검증된 접근 매트릭스

| 사용자(그룹) | SSH | PG정적 | PG동적 | Redis | 웹 | k8s |
|---|---|---|---|---|---|---|
| alice (sre) | ✅ | ⛔ | ⛔ | ⛔ | ✅ | ✅ |
| carol (dba) | ⛔ | ✅ | ✅ | ✅ | ⛔ | ⛔ |
| bob (none) | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ |

## 6. GitOps & 신청 흐름

```
[사용자] 웹폼 신청 → access.json 수정 PR
[승인자] PR 머지
[CI/운영자] terraform apply → Boundary 권한 반영
[운영자] 리소스 추가/삭제는 운영자 페이지에서 즉시 apply
```
단일 소스: `terraform/access.json`(권한) · `terraform/targets.json`(리소스)

## 7. 컴포넌트 / 포트 (로컬 PoC)

| 컴포넌트 | 주소 | 비고 |
|----------|------|------|
| Boundary | http://127.0.0.1:9200 | admin / password |
| Keycloak | http://127.0.0.1:8081 | admin / admin |
| lldap | http://127.0.0.1:17170 | admin / adminpassword |
| Vault | http://127.0.0.1:8200 | token: root |
| 신청 포털 | http://127.0.0.1:8090 | / 신청, /admin 운영자 |
| 타겟 | ssh:2222 · pg:5432 · redis:6379 · web:8089 · k8s:26443 | Docker |

## 8. 실무 전환 체크리스트

- [ ] `boundary dev` → 프로덕션(PostgreSQL 백엔드 + KMS), 워커를 각 망에 분산 배치
- [ ] lldap → 실제 **AD/LDAP**, Keycloak federation 그대로
- [ ] **MFA** 강제 (Keycloak)
- [ ] 리소스는 **동적 호스트 카탈로그 + 태그** 로 자동 발견 (수천 대 대응)
- [ ] 권한은 **그룹 기준**, 스코프를 팀/환경별 project 로 분리
- [ ] 신청·승인·만료·검토가 빡세지면 **IGA**(midPoint/상용) 도입
- [ ] 세션 녹화 필요 시 **HCP/Enterprise**
- [ ] 타겟 **직노출 포트 차단** → Boundary 경유만 허용

## 9. 오픈소스 스택 요약

| 역할 | 사용(PoC) | 대안 |
|------|-----------|------|
| 디렉터리 | lldap | OpenLDAP, 389DS, FreeIPA, AD |
| IdP/SSO | Keycloak | Authentik, Zitadel |
| 접근제어 | Boundary (OSS) | (AWS SSM — AWS 한정) |
| 시크릿 | Vault | — |
| IaC | Terraform | — |
| 신청(IGA) | 자체 웹포털 | midPoint, Opal, Indent |
