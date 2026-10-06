variable "name" {
  description = "Cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Upgrade one minor version at a time."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.35."
  }
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the control-plane ENIs and nodes."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "CMK for Secrets envelope encryption, EBS volumes and control-plane logs."
  type        = string
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API publicly (restricted by CIDR). Keep false in prod."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Never expose the Kubernetes API to 0.0.0.0/0."
  }
}

variable "endpoint_private_access_cidrs" {
  description = "Private CIDRs (VPN, bastion, CI runners in VPC) allowed to reach the private API endpoint."
  type        = list(string)
  default     = []
}

variable "service_ipv4_cidr" {
  description = "CIDR for Kubernetes Services. Must not overlap the VPC."
  type        = string
  default     = "172.20.0.0/16"
}

variable "support_type" {
  description = "STANDARD (auto-upgrade at end of standard support) or EXTENDED (paid extended support)."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "zonal_shift_enabled" {
  description = "Enable ARC zonal shift for the cluster."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block cluster deletion."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Control-plane log retention."
  type        = number
  default     = 90
}

variable "admin_principal_arns" {
  description = "IAM role ARNs granted cluster-admin via access entries (e.g. SSO admin role)."
  type        = list(string)

  validation {
    condition     = length(var.admin_principal_arns) > 0
    error_message = "At least one admin principal is required, otherwise nobody can access the cluster."
  }
}

variable "readonly_principal_arns" {
  description = "IAM role ARNs granted cluster-wide read-only access."
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Managed node groups keyed by name."
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

  validation {
    condition     = alltrue([for ng in values(var.node_groups) : contains(["ON_DEMAND", "SPOT"], ng.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "endpoint_private_access_security_group_ids" {
  description = "Security groups (e.g. bastion) allowed to reach the private API endpoint."
  type        = list(string)
  default     = []
}
