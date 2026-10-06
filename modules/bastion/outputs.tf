output "instance_id" {
  description = "Bastion instance ID (use with `aws ssm start-session --target`)."
  value       = aws_instance.this.id
}

output "role_arn" {
  description = "IAM role of the bastion (granted EKS admin via access entry)."
  value       = aws_iam_role.this.arn
}

output "security_group_id" {
  description = "Bastion security group ID."
  value       = aws_security_group.this.id
}

output "session_log_group" {
  description = "CloudWatch log group with recorded bastion shell sessions."
  value       = var.session_logging ? aws_cloudwatch_log_group.sessions[0].name : null
}
