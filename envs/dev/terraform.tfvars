# Dev: slim, free-plan friendly. EKS + bastion only; classic app tier disabled.
# Account-specific values (account id, admin ARN) go in a git-ignored
# `local.auto.tfvars`, which overrides this file.
project        = "acme"
environment    = "dev"
aws_account_id = "111111111111" # overridden in local.auto.tfvars
region         = "us-east-1"
repository     = "github.com/vinaysinghhata5-oss/terraform-aws-platform"
owner          = "platform-team"

# Feature toggles
enable_app_tier = false # ALB + EC2 ASG + RDS off to save credits
enable_bastion  = true

# Network - single NAT gateway, 2 AZs (EKS minimum)
vpc_cidr                = "10.10.0.0/16"
az_count                = 2
single_nat_gateway      = true
vpc_interface_endpoints = [] # traffic goes via NAT; endpoints cost ~$7/month each per AZ

# EKS - private API only; kubectl runs on the bastion (SSM Session Manager)
eks_version                = "1.35"
eks_endpoint_public_access = false
eks_support_type           = "STANDARD"
eks_admin_principal_arns   = ["arn:aws:iam::111111111111:role/platform-admin"] # overridden in local.auto.tfvars

eks_node_groups = {
  general = {
    instance_types = ["m7i-flex.large"] # free-tier eligible: 2 vCPU / 8 GiB
    min_size       = 1
    max_size       = 2
    desired_size   = 1
    disk_size      = 30
  }
}

bastion_instance_type = "t3.micro" # free-tier eligible

# App tier (unused while enable_app_tier = false)
certificate_arn          = null
allowed_ingress_cidrs    = ["203.0.113.0/24"]
instance_type            = "t3.micro"
asg_min_size             = 1
asg_max_size             = 2
asg_desired_capacity     = 1
db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 1

# Safety - dev is disposable: destroy cleanly when not practising
deletion_protection = false
log_retention_days  = 7
