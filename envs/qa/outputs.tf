output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "app_bucket" {
  description = "Application data bucket."
  value       = module.app_bucket.bucket_id
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Command to configure kubectl (run on the bastion or over VPN)."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "bastion_instance_id" {
  description = "Bastion instance ID."
  value       = var.enable_bastion ? module.bastion[0].instance_id : null
}

output "bastion_connect_command" {
  description = "Open a shell on the bastion via SSM Session Manager."
  value       = var.enable_bastion ? "aws ssm start-session --target ${module.bastion[0].instance_id} --region ${var.region}" : null
}

output "alb_dns_name" {
  description = "Public endpoint of the application (app tier only)."
  value       = var.enable_app_tier ? module.alb[0].alb_dns_name : null
}

output "db_endpoint" {
  description = "RDS endpoint (app tier only)."
  value       = var.enable_app_tier ? module.rds[0].endpoint : null
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials (app tier only)."
  value       = var.enable_app_tier ? module.rds[0].master_user_secret_arn : null
}
