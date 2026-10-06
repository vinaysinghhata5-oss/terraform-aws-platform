variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for SSE-KMS. null falls back to SSE-S3 (required for ALB access logs)."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow destroying a non-empty bucket. Never true in prod."
  type        = bool
  default     = false
}

variable "expiration_days" {
  description = "Expire current object versions after N days. null = keep forever."
  type        = number
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Delete noncurrent object versions after N days."
  type        = number
  default     = 90
}

variable "additional_policy_json" {
  description = "Extra bucket policy statements merged with the TLS-enforcement policy."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
