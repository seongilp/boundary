# ────────────────────────────────────────────────────────────────
# Roles + Grants — 누가 어떤 target 에 authorize-session 가능한가.
#   alice → ssh-target
#   carol → pg-target, pg-dyn-target
#   bob   → 없음
# ────────────────────────────────────────────────────────────────

resource "boundary_role" "ssh_connect" {
  name            = "ssh-connect"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = ["ids=${boundary_target.ssh.id};actions=authorize-session,read"]
  principal_ids   = [boundary_user.this["alice"].id]
}

resource "boundary_role" "pg_connect" {
  name            = "pg-connect"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = ["ids=${boundary_target.pg.id};actions=authorize-session,read"]
  principal_ids   = [boundary_user.this["carol"].id]
}

resource "boundary_role" "pg_dyn_connect" {
  name            = "pg-dyn-connect"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = ["ids=${boundary_target.pg_dynamic.id};actions=authorize-session,read"]
  principal_ids   = [boundary_user.this["carol"].id]
}

# boundary dev 가 자동 생성하는 'Authenticated User Grants' 역할은
# 인증된 모든 사용자에게 target authorize-session 을 준다(데모 무력화).
# authorize-session 만 회수(list,read 유지)하는 한 줄 보정 — dev 모드 한정 escape hatch.
resource "null_resource" "tighten_default_grants" {
  triggers = { version = "1" }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/tighten-default-grants.sh '${var.boundary_addr}' '${var.auth_method_id}' '${var.admin_login}' '${var.admin_password}'"
  }

  depends_on = [
    boundary_role.ssh_connect,
    boundary_role.pg_connect,
    boundary_role.pg_dyn_connect,
  ]
}
