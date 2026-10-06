variable "project" {
  description = "Project prefix."
  type        = string
  default     = "acme"
}

variable "environment" {
  description = "Environment this account hosts (dev, qa, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "prod"], var.environment)
    error_message = "environment must be one of dev, qa, prod."
  }
}

variable "aws_account_id" {
  description = "Target AWS account ID."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repo."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}
