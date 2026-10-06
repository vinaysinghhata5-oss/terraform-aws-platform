variable "project" {
  description = "Project name used as a prefix for resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of dev, qa, prod."
  }
}

variable "aws_account_id" {
  description = "AWS account this environment lives in (one account per environment)."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "repository" {
  description = "Source repository, added as a tag for traceability."
  type        = string
}

variable "owner" {
  description = "Owning team, added as a tag."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC /16 CIDR. Must not overlap between environments (peering / TGW)."
  type        = string
}

variable "az_count" {
  description = "Number of AZs."
  type        = number
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway to save cost (non-prod only)."
  type        = bool
}

variable "certificate_arn" {
  description = "ACM certificate for the ALB HTTPS listener."
  type        = string
  default     = null
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to hit the ALB."
  type        = list(string)
}

variable "instance_type" {
  description = "App instance type."
  type        = string
}

variable "asg_min_size" {
  description = "ASG min size."
  type        = number
}

variable "asg_max_size" {
  description = "ASG max size."
  type        = number
}

variable "asg_desired_capacity" {
  description = "ASG initial desired capacity."
  type        = number
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ."
  type        = bool
}

variable "db_backup_retention_days" {
  description = "RDS backup retention days."
  type        = number
}

variable "deletion_protection" {
  description = "Enable deletion protection on stateful resources."
  type        = bool
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
}

variable "waf_acl_arn" {
  description = "Optional WAFv2 web ACL ARN to attach to the ALB."
  type        = string
  default     = null
}

variable "vpc_interface_endpoints" {
  description = "Interface VPC endpoints to create."
  type        = list(string)
  default     = []
}

variable "eks_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "eks_endpoint_public_access" {
  description = "Expose the EKS API publicly (CIDR restricted)."
  type        = bool
}

variable "eks_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to the public EKS API."
  type        = list(string)
  default     = []
}

variable "eks_endpoint_private_access_cidrs" {
  description = "Private CIDRs (VPN / bastion) allowed to the private EKS API."
  type        = list(string)
  default     = []
}

variable "eks_support_type" {
  description = "EKS upgrade policy: STANDARD or EXTENDED."
  type        = string
  default     = "STANDARD"
}

variable "eks_zonal_shift_enabled" {
  description = "Enable ARC zonal shift."
  type        = bool
  default     = false
}

variable "eks_admin_principal_arns" {
  description = "IAM roles with cluster-admin."
  type        = list(string)
}

variable "eks_readonly_principal_arns" {
  description = "IAM roles with cluster read-only access."
  type        = list(string)
  default     = []
}

variable "eks_node_groups" {
  description = "EKS managed node groups (see modules/eks for the schema)."
  type = map(object({
    instance_types = list(string)
    capacity_type  = optional(string, "ON_DEMAND")
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = optional(number, 50)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
}
