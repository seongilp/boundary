# Boundary provider — admin password 로 인증 (dev 모드).
provider "boundary" {
  addr                   = var.boundary_addr
  auth_method_id         = var.auth_method_id
  auth_method_login_name = var.admin_login
  auth_method_password   = var.admin_password
}

# Vault provider — dev root 토큰 (학습 전용).
provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}
