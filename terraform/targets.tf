# ────────────────────────────────────────────────────────────────
# Targets (리소스). 주소를 직접 지정 → host catalog 불필요.
#   ssh-target     : SSH 서버,        정적 brokering (devuser/devpass)
#   pg-target      : PostgreSQL,       정적 brokering (appuser/apppass)
#   pg-dyn-target  : PostgreSQL,       Vault 동적 자격증명
# ────────────────────────────────────────────────────────────────

resource "boundary_target" "ssh" {
  name         = "ssh-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = var.ssh_port
  address      = var.ssh_address

  brokered_credential_source_ids = [boundary_credential_username_password.ssh.id]
}

resource "boundary_target" "pg" {
  name         = "pg-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = var.pg_port
  address      = var.pg_address

  brokered_credential_source_ids = [boundary_credential_username_password.pg.id]
}

resource "boundary_target" "pg_dynamic" {
  name         = "pg-dyn-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = var.pg_port
  address      = var.pg_address

  brokered_credential_source_ids = [boundary_credential_library_vault.pg_dynamic.id]
}

# SSH/DB 가 아닌 TCP 리소스도 동일하게 통제된다.
resource "boundary_target" "redis" {
  name         = "redis-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = var.redis_port
  address      = var.redis_address
}

resource "boundary_target" "web" {
  name         = "web-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = var.web_port
  address      = var.web_address
}

# Kubernetes API 서버 — 클러스터 전체의 제어판. 가장 통제가치 높은 타겟 중 하나.
resource "boundary_target" "k8s" {
  name         = "k8s-target"
  type         = "tcp"
  scope_id     = var.project_scope_id
  default_port = var.k8s_port
  address      = var.k8s_address
}
