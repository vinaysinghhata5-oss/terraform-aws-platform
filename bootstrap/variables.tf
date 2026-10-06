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

variable "budget_email" {
  description = "Email for monthly cost alerts. null disables the budget."
  type        = string
  default     = null
  sensitive   = true # keep it out of public CI logs
}

variable "budget_limit_usd" {
  description = "Monthly budget in USD; alerts at 50%, 80% and 100% (forecast)."
  type        = number
  default     = 20
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID. Set with github_repo_id when the repo uses immutable OIDC subjects (gh api repos/OWNER/REPO/actions/oidc/customization/sub)."
  type        = string
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID (see github_owner_id)."
  type        = string
  default     = null
}

variable "admin_users" {
  description = "IAM user names allowed to assume platform-admin (with MFA)."
  type        = list(string)
  default     = []
}

variable "developer_users" {
  description = "IAM user names allowed to assume developer-readonly (with MFA)."
  type        = list(string)
  default     = []
}
