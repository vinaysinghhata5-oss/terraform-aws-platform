variable "name" {
  description = "ALB name (max 32 chars)."
  type        = string

  validation {
    condition     = length(var.name) <= 32
    error_message = "ALB name must be 32 characters or fewer."
  }
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR, used to scope ALB egress."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "target_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Target group health-check path."
  type        = string
  default     = "/health"
}

variable "certificate_arn" {
  description = "ACM certificate ARN. Required for prod; null disables HTTPS."
  type        = string
  default     = null
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB. Restrict non-prod to office/VPN ranges."
  type        = list(string)
}

variable "access_logs_bucket" {
  description = "S3 bucket (SSE-S3) for ALB access logs."
  type        = string
}

variable "waf_acl_arn" {
  description = "Optional WAFv2 web ACL to associate."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Prevent accidental ALB deletion."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
