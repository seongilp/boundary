# ────────────────────────────────────────────────────────────────
# OIDC(SSO) 인증 — Keycloak 연동.
#   사용자는 회사 계정(Keycloak)으로 로그인. 권한은 '그룹' 기준으로 부여.
#   managed group: OIDC 토큰의 groups claim 으로 자동 분류 (sre, dba)
#   → 개인이 아니라 그룹에 role 부여 (규모 확장 시 핵심)
# ────────────────────────────────────────────────────────────────

resource "boundary_auth_method_oidc" "keycloak" {
  name                 = "keycloak"
  description          = "Keycloak OIDC (SSO)"
  scope_id             = var.global_scope_id
  issuer               = var.oidc_issuer
  client_id            = var.oidc_client_id
  client_secret        = var.oidc_client_secret
  signing_algorithms   = ["RS256"]
  api_url_prefix = var.boundary_addr
  state          = "active-public"
  # primary 로 두어야 OIDC 첫 로그인 시 User 가 자동 생성됨.
  # (password 사용자는 이미 Terraform 으로 명시 생성돼 있어 영향 없음)
  is_primary_for_scope = true
}

# OIDC 첫 로그인 시 User 자동생성이 되려면 scope 의 primary 가 OIDC 여야 한다.
# provider 의 is_primary_for_scope 만으로 scope 가 안 바뀌는 경우가 있어 CLI 로 확정.
resource "null_resource" "oidc_primary" {
  triggers = { amid = boundary_auth_method_oidc.keycloak.id }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      export BOUNDARY_ADDR='${var.boundary_addr}'
      export BOUNDARY_TOKEN=$(BDAY_PW='${var.admin_password}' boundary authenticate password \
        -auth-method-id='${var.auth_method_id}' -login-name='${var.admin_login}' \
        -password=env://BDAY_PW -keyring-type=none -format=json | jq -r '.item.attributes.token')
      boundary scopes update -id '${var.global_scope_id}' \
        -primary-auth-method-id='${boundary_auth_method_oidc.keycloak.id}' \
        -token=env://BOUNDARY_TOKEN >/dev/null
      echo "global primary -> ${boundary_auth_method_oidc.keycloak.id}"
    EOT
  }

  depends_on = [boundary_auth_method_oidc.keycloak]
}

resource "boundary_managed_group" "sre" {
  name           = "sre"
  description    = "Keycloak 'sre' 그룹"
  auth_method_id = boundary_auth_method_oidc.keycloak.id
  filter         = "\"sre\" in \"/token/groups\""
}

resource "boundary_managed_group" "dba" {
  name           = "dba"
  description    = "Keycloak 'dba' 그룹"
  auth_method_id = boundary_auth_method_oidc.keycloak.id
  filter         = "\"dba\" in \"/token/groups\""
}

locals {
  sre_targets = ["ssh-target", "web-target", "k8s-target"]
  dba_targets = ["pg-target", "pg-dyn-target", "redis-target"]
}

# 그룹 → 리소스 권한 (principal = managed group)
resource "boundary_role" "oidc_sre" {
  name            = "oidc-sre"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = [for t in local.sre_targets : "ids=${local.target_ids[t]};actions=authorize-session,read"]
  principal_ids   = [boundary_managed_group.sre.id]
}

resource "boundary_role" "oidc_dba" {
  name            = "oidc-dba"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = [for t in local.dba_targets : "ids=${local.target_ids[t]};actions=authorize-session,read"]
  principal_ids   = [boundary_managed_group.dba.id]
}
