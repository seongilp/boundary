# ────────────────────────────────────────────────────────────────
# Roles + Grants — 데이터 기반(access.json) 으로 자동 생성.
#   access.json: { "사용자": ["허용 target 이름", ...] }  ← 웹 신청 포털이 이 파일만 수정해 PR
#   여기서 (사용자 × target) 마다 role 하나씩 생성.
# ────────────────────────────────────────────────────────────────

locals {
  # 단일 소스: 누가 어떤 target 에 접근 가능한가
  access = jsondecode(file("${path.module}/access.json"))

  # target 이름 → target id 매핑
  target_ids = {
    "ssh-target"    = boundary_target.ssh.id
    "pg-target"     = boundary_target.pg.id
    "pg-dyn-target" = boundary_target.pg_dynamic.id
    "redis-target"  = boundary_target.redis.id
    "web-target"    = boundary_target.web.id
    "k8s-target"    = boundary_target.k8s.id
  }

  # (사용자,target) 쌍으로 평탄화
  grants = flatten([
    for user, targets in local.access : [
      for t in targets : { user = user, target = t }
    ]
  ])
}

resource "boundary_role" "access" {
  for_each = { for g in local.grants : "${g.user}--${g.target}" => g }

  name            = "${each.value.user}--${each.value.target}"
  scope_id        = var.project_scope_id
  grant_scope_ids = ["this"]
  grant_strings   = ["ids=${local.target_ids[each.value.target]};actions=authorize-session,read"]
  principal_ids   = [boundary_user.this[each.value.user].id]
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

  depends_on = [boundary_role.access]
}
