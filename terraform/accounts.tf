# ────────────────────────────────────────────────────────────────
# 사용자(신원) — Boundary 로컬 계정(password) + user.
#   alice : SSH 담당
#   carol : DB(DBA) 담당
#   bob   : 권한 없음
# auth method 가 global 스코프라 user 도 global 에 둔다.
# ────────────────────────────────────────────────────────────────

locals {
  demo_users = ["alice", "carol", "bob"]
}

resource "boundary_account_password" "this" {
  for_each       = toset(local.demo_users)
  auth_method_id = var.auth_method_id
  login_name     = each.key
  password       = var.demo_password
  name           = each.key
}

resource "boundary_user" "this" {
  for_each    = toset(local.demo_users)
  scope_id    = var.global_scope_id
  name        = each.key
  account_ids = [boundary_account_password.this[each.key].id]
}
