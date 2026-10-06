project        = "acme"
environment    = "qa"
aws_account_id = "222222222222" # TODO: replace with your qa account ID
region         = "us-east-1"
repository     = "github.com/vinaysinghhata5-oss/terraform-aws-platform"
owner          = "platform-team"

# Network - non-overlapping CIDRs per environment
vpc_cidr           = "10.20.0.0/16"
az_count           = 2
single_nat_gateway = true

# Edge
certificate_arn       = null
allowed_ingress_cidrs = ["203.0.113.0/24"] # office / VPN only

# Compute
instance_type        = "t3.small"
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 2

# Database
db_instance_class        = "db.t4g.small"
db_multi_az              = false
db_backup_retention_days = 7

# Safety
deletion_protection = true
log_retention_days  = 90

# EKS
eks_version                      = "1.35"
eks_endpoint_public_access       = true
eks_endpoint_public_access_cidrs = ["203.0.113.0/24"] # office / VPN egress only
eks_support_type                 = "STANDARD"
eks_admin_principal_arns         = ["arn:aws:iam::222222222222:role/platform-admin"] # TODO: your SSO admin role
eks_readonly_principal_arns      = ["arn:aws:iam::222222222222:role/developer"]
vpc_interface_endpoints          = ["ecr.api", "ecr.dkr", "sts"]

eks_node_groups = {
  general = {
    instance_types = ["m6i.large"]
    min_size       = 2
    max_size       = 5
    desired_size   = 2
  }
}
