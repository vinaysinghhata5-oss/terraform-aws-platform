project        = "acme"
environment    = "prod"
aws_account_id = "333333333333" # TODO: replace with your prod account ID
region         = "us-east-1"
repository     = "github.com/vinaysinghhata5-oss/terraform-aws-platform"
owner          = "platform-team"

# Network - non-overlapping CIDRs per environment
vpc_cidr           = "10.30.0.0/16"
az_count           = 3
single_nat_gateway = false

# Edge
certificate_arn       = "arn:aws:acm:us-east-1:333333333333:certificate/REPLACE-ME"
allowed_ingress_cidrs = ["0.0.0.0/0"] # public, HTTPS only
waf_acl_arn           = null          # TODO: set your WAFv2 web ACL ARN

# Compute
instance_type        = "m6i.large"
asg_min_size         = 3
asg_max_size         = 10
asg_desired_capacity = 3

# Database
db_instance_class        = "db.m6g.large"
db_multi_az              = true
db_backup_retention_days = 35

# Safety
deletion_protection = true
log_retention_days  = 365

# EKS - private API only: reach it over VPN / Direct Connect / bastion
eks_version                       = "1.35"
eks_endpoint_public_access        = false
eks_endpoint_private_access_cidrs = ["10.100.0.0/16"] # TODO: VPN / corporate network CIDR
eks_support_type                  = "STANDARD"
eks_zonal_shift_enabled           = true
eks_admin_principal_arns          = ["arn:aws:iam::333333333333:role/platform-admin"] # TODO: your SSO admin role
eks_readonly_principal_arns       = ["arn:aws:iam::333333333333:role/developer"]
vpc_interface_endpoints           = ["ecr.api", "ecr.dkr", "sts", "ec2", "logs", "ssm", "ssmmessages", "ec2messages"]

eks_node_groups = {
  # Small, stable on-demand pool for cluster-critical add-ons (CoreDNS, controllers).
  system = {
    instance_types = ["m6i.large"]
    min_size       = 3 # one per AZ
    max_size       = 6
    desired_size   = 3
    labels         = { "workload-type" = "system" }
    taints         = [{ key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" }]
  }
  # Application pool.
  general = {
    instance_types = ["m6i.xlarge", "m6a.xlarge", "m7i.xlarge"]
    min_size       = 3
    max_size       = 15
    desired_size   = 3
    disk_size      = 100
    labels         = { "workload-type" = "general" }
  }
}

# Feature toggles
enable_app_tier = true
enable_bastion  = true
