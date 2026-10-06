project        = "acme"
environment    = "dev"
aws_account_id = "111111111111" # TODO: replace with your dev account ID
region         = "us-east-1"
repository     = "github.com/vinaysinghhata5-oss/terraform-aws-platform"
owner          = "platform-team"

# Network - non-overlapping CIDRs per environment
vpc_cidr           = "10.10.0.0/16"
az_count           = 2
single_nat_gateway = true

# Edge
certificate_arn       = null
allowed_ingress_cidrs = ["203.0.113.0/24"] # office / VPN only

# Compute
instance_type        = "t3.micro"
asg_min_size         = 1
asg_max_size         = 2
asg_desired_capacity = 1

# Database
db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 1

# Safety
deletion_protection = false
log_retention_days  = 30

# EKS
eks_version                      = "1.35"
eks_endpoint_public_access       = true
eks_endpoint_public_access_cidrs = ["203.0.113.0/24"] # office / VPN egress only
eks_support_type                 = "STANDARD"
eks_admin_principal_arns         = ["arn:aws:iam::111111111111:role/platform-admin"] # TODO: your SSO admin role
vpc_interface_endpoints          = []                                                # dev saves cost; traffic goes via NAT

eks_node_groups = {
  general = {
    instance_types = ["t3.large", "t3a.large", "m5.large"] # diversify for Spot capacity
    capacity_type  = "SPOT"
    min_size       = 1
    max_size       = 4
    desired_size   = 2
  }
}
