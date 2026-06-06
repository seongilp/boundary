# ────────────────────────────────────────────────────────────────
# 입력 변수. 실제 값은 terraform.tfvars 에 둔다 (시크릿은 git 제외).
# ────────────────────────────────────────────────────────────────

# Boundary 컨트롤러
variable "boundary_addr" {
  type    = string
  default = "http://127.0.0.1:9200"
}

variable "admin_login" {
  type    = string
  default = "admin"
}

variable "admin_password" {
  type      = string
  default   = "password"
  sensitive = true
}

# boundary dev 가 고정 생성하는 ID (id-suffix=1234567890)
variable "auth_method_id" {
  type    = string
  default = "ampw_1234567890"
}

variable "global_scope_id" {
  type    = string
  default = "global"
}

variable "project_scope_id" {
  type    = string
  default = "p_1234567890"
}

# 실습 사용자 공통 비밀번호
variable "demo_password" {
  type      = string
  default   = "demo1234"
  sensitive = true
}

# SSH 타겟
variable "ssh_address" {
  type    = string
  default = "127.0.0.1"
}
variable "ssh_port" {
  type    = number
  default = 2222
}

# PostgreSQL 타겟
variable "pg_address" {
  type    = string
  default = "127.0.0.1"
}
variable "pg_port" {
  type    = number
  default = 5432
}
variable "pg_db" {
  type    = string
  default = "appdb"
}
variable "pg_admin_user" {
  type    = string
  default = "appuser"
}
variable "pg_admin_password" {
  type      = string
  default   = "apppass"
  sensitive = true
}

# 정적 brokering 용 서버/DB 자격증명
variable "ssh_login_user" {
  type    = string
  default = "devuser"
}
variable "ssh_login_password" {
  type      = string
  default   = "devpass"
  sensitive = true
}

# Redis 타겟
variable "redis_address" {
  type    = string
  default = "127.0.0.1"
}
variable "redis_port" {
  type    = number
  default = 6379
}

# 웹앱 타겟 (HTTP)
variable "web_address" {
  type    = string
  default = "127.0.0.1"
}
variable "web_port" {
  type    = number
  default = 8089
}

# Vault
variable "vault_addr" {
  type    = string
  default = "http://127.0.0.1:8200"
}
variable "vault_token" {
  type      = string
  default   = "root" # dev 모드 root 토큰 (학습 전용)
  sensitive = true
}
# Vault 가 내부 네트워크에서 postgres 에 접속할 주소 (compose 서비스명)
variable "vault_pg_connection_url" {
  type    = string
  default = "postgresql://{{username}}:{{password}}@postgres-target:5432/appdb?sslmode=disable"
}
