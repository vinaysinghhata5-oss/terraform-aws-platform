output "security_group_id" {
  description = "App security group ID."
  value       = aws_security_group.app.id
}

output "asg_name" {
  description = "Auto Scaling group name."
  value       = aws_autoscaling_group.this.name
}

output "instance_role_arn" {
  description = "IAM role ARN used by the instances."
  value       = aws_iam_role.this.arn
}
