output "alb_dns_name" {
  description = "Public endpoint of the application."
  value       = module.alb.alb_dns_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "db_endpoint" {
  description = "RDS endpoint."
  value       = module.rds.endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials (value is never exposed)."
  value       = module.rds.master_user_secret_arn
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
  description = "Command to configure kubectl."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
