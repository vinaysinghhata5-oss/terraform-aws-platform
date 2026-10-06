variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR, used to scope database egress."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for instances."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group allowed to reach the app."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group to register instances with."
  type        = string
}

variable "app_port" {
  description = "Application port."
  type        = number
  default     = 8080
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "min_size" {
  description = "ASG minimum size."
  type        = number
}

variable "max_size" {
  description = "ASG maximum size."
  type        = number
}

variable "desired_capacity" {
  description = "Initial desired capacity (then owned by autoscaling)."
  type        = number
}

variable "user_data_base64" {
  description = "Base64 encoded user data."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "KMS key for EBS encryption and secret decryption."
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN of the DB master credentials."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
