# ────────────────────────────────────────────────────────────────
# Vault — 동적 PostgreSQL 자격증명 발급 설정.
#   접속할 때마다 임시 DB 계정 생성 → TTL 만료 시 자동 폐기.
# ────────────────────────────────────────────────────────────────

resource "vault_mount" "db" {
  path = "database"
  type = "database"
}

resource "vault_database_secret_backend_connection" "appdb" {
  backend       = vault_mount.db.path
  name          = "appdb"
  allowed_roles = ["boundary-role"]

  postgresql {
    connection_url = var.vault_pg_connection_url
    username       = var.pg_admin_user
    password       = var.pg_admin_password
  }
}

resource "vault_database_secret_backend_role" "boundary" {
  backend = vault_mount.db.path
  name    = "boundary-role"
  db_name = vault_database_secret_backend_connection.appdb.name

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT CONNECT ON DATABASE ${var.pg_db} TO \"{{name}}\";",
    "GRANT USAGE ON SCHEMA public TO \"{{name}}\";",
  ]

  default_ttl = 180 # 3분
  max_ttl     = 600 # 10분
}

# Boundary 가 Vault 에서 자격증명을 읽을 때 쓸 정책 + 토큰.
resource "vault_policy" "boundary" {
  name   = "boundary"
  policy = <<-EOT
    path "auth/token/lookup-self"  { capabilities = ["read"] }
    path "auth/token/renew-self"   { capabilities = ["update"] }
    path "auth/token/revoke-self"  { capabilities = ["update"] }
    path "sys/leases/renew"        { capabilities = ["update"] }
    path "sys/leases/revoke"       { capabilities = ["update"] }
    path "sys/capabilities-self"   { capabilities = ["update"] }
    path "database/creds/boundary-role" { capabilities = ["read"] }
  EOT
}

resource "vault_token" "boundary" {
  policies          = [vault_policy.boundary.name]
  no_default_policy = true
  no_parent         = true # Boundary 는 orphan 토큰을 요구
  period            = "60m" # periodic 토큰 (Boundary 가 스스로 갱신)
  renewable         = true
}
