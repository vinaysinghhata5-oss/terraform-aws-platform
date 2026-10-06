output "state_bucket" {
  description = "S3 bucket for Terraform state - put this in envs/<env>/backend.tf."
  value       = module.state_bucket.bucket_id
}

output "plan_role_arn" {
  description = "Role assumed by PR / drift plans."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role assumed by gated apply jobs."
  value       = aws_iam_role.apply.arn
}

output "platform_admin_role_arn" {
  description = "Role admins assume (with MFA)."
  value       = aws_iam_role.platform_admin.arn
}

output "developer_role_arn" {
  description = "Role developers assume (with MFA)."
  value       = aws_iam_role.developer.arn
}
