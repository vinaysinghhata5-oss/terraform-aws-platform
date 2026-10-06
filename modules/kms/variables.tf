variable "alias" {
  description = "KMS alias name (without the alias/ prefix)."
  type        = string
}

variable "description" {
  description = "Human readable description of the key."
  type        = string
}

variable "deletion_window_in_days" {
  description = "Waiting period before key deletion. Use 30 in prod."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "allow_autoscaling_service_role" {
  description = "Let the EC2 Auto Scaling service-linked role use this key (needed for encrypted ASG volumes)."
  type        = bool
  default     = false
}
