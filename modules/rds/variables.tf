variable "name" {
  description = "DB identifier."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "database_subnet_ids" {
  description = "Isolated database subnets."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "App tier SG allowed to connect."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version; minor upgrades are applied automatically."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username. Password is managed by Secrets Manager."
  type        = string
  default     = "app_admin"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Deploy a synchronous standby in another AZ."
  type        = bool
}

variable "backup_retention_period" {
  description = "Days to retain automated backups."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block deletes and take a final snapshot."
  type        = bool
}

variable "kms_key_arn" {
  description = "KMS key for storage, secret and Performance Insights encryption."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "additional_ingress_security_group_ids" {
  description = "Other security groups (e.g. EKS cluster SG) allowed to connect."
  type        = list(string)
  default     = []
}
