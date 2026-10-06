output "alb_dns_name" {
  description = "Public DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "security_group_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group ARN for the application tier."
  value       = aws_lb_target_group.this.arn
}
