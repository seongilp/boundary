# ────────────────────────────────────────────────────────────────
# Credential Stores
#   static : 서버/DB 고정 비번 brokering (devpass, apppass)
#   vault  : 동적 자격증명 (위 vault.tf 의 boundary-role)
# ────────────────────────────────────────────────────────────────

# --- 정적 자격증명 (brokering) ---
resource "boundary_credential_store_static" "static" {
  name     = "demo-cred-store"
  scope_id = var.project_scope_id
}

resource "boundary_credential_username_password" "ssh" {
  name                = "ssh-cred"
  credential_store_id = boundary_credential_store_static.static.id
  username            = var.ssh_login_user
  password            = var.ssh_login_password
}

resource "boundary_credential_username_password" "pg" {
  name                = "pg-cred"
  credential_store_id = boundary_credential_store_static.static.id
  username            = var.pg_admin_user
  password            = var.pg_admin_password
}

# --- Vault 동적 자격증명 ---
resource "boundary_credential_store_vault" "vault" {
  name     = "vault-store"
  scope_id = var.project_scope_id
  address  = var.vault_addr
  token    = vault_token.boundary.client_token
}

resource "boundary_credential_library_vault" "pg_dynamic" {
  name                = "pg-dynamic"
  credential_store_id = boundary_credential_store_vault.vault.id
  path                = "database/creds/boundary-role"
  http_method         = "GET"
  credential_type     = "username_password"
}
