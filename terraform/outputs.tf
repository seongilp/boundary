output "ssh_target_id" {
  description = "SSH target ID"
  value       = boundary_target.ssh.id
}

output "pg_target_id" {
  description = "PostgreSQL target ID (정적 brokering)"
  value       = boundary_target.pg.id
}

output "pg_dyn_target_id" {
  description = "PostgreSQL target ID (Vault 동적 자격증명)"
  value       = boundary_target.pg_dynamic.id
}

output "extra_target_ids" {
  description = "targets.json 기반 동적 target ID 들"
  value       = { for name, t in boundary_target.extra : name => t.id }
}

output "users" {
  description = "생성된 Boundary 사용자"
  value       = { for k, u in boundary_user.this : k => u.id }
}
