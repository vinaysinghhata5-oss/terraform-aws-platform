variable "name" {
  description = "Name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the bastion (needs NAT or SSM VPC endpoints)."
  type        = string
}

variable "instance_type" {
  description = "Instance type. t3.micro is free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "cluster_name" {
  description = "EKS cluster the bastion manages."
  type        = string
}

variable "kubernetes_version" {
  description = "Cluster minor version, used to pick a matching kubectl."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the root volume."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "session_logging" {
  description = "Record shell sessions to CloudWatch and manage Session Manager preferences (idle/max timeouts). One per account+region."
  type        = bool
  default     = true
}

variable "session_log_retention_days" {
  description = "Retention for recorded sessions. They are audit evidence, so keep at least a year."
  type        = number
  default     = 365

  validation {
    condition     = var.session_log_retention_days >= 365
    error_message = "Session recordings are audit evidence: keep them at least 365 days."
  }
}
