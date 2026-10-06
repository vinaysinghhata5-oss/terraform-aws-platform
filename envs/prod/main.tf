locals {
  name = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "current" {}

# ---------------- Encryption ----------------
module "kms" {
  source = "../../modules/kms"

  alias                   = local.name
  description             = "Platform key for ${local.name}"
  deletion_window_in_days = var.deletion_protection ? 30 : 7

  allow_autoscaling_service_role = true
}

# ---------------- Network ----------------
module "vpc" {
  source = "../../modules/vpc"

  name                    = local.name
  cidr_block              = var.vpc_cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  kms_key_arn             = module.kms.key_arn
  flow_log_retention_days = var.log_retention_days
  interface_endpoints     = var.vpc_interface_endpoints

  # Lets the AWS Load Balancer Controller discover subnets for Ingress / Service LBs.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

# ---------------- Storage ----------------
data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AllowELBLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.name}-alb-logs-${data.aws_caller_identity.current.account_id}/${local.name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }
}

module "alb_logs_bucket" {
  source = "../../modules/s3-bucket"

  bucket_name            = "${local.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  kms_key_arn            = null # ALB log delivery only supports SSE-S3
  expiration_days        = var.log_retention_days
  force_destroy          = !var.deletion_protection
  additional_policy_json = data.aws_iam_policy_document.alb_logs.json
}

module "app_bucket" {
  source = "../../modules/s3-bucket"

  bucket_name   = "${local.name}-app-data-${data.aws_caller_identity.current.account_id}"
  kms_key_arn   = module.kms.key_arn
  force_destroy = !var.deletion_protection
}

# ---------------- Edge ----------------
module "alb" {
  source = "../../modules/alb"

  name                  = local.name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr_block        = module.vpc.vpc_cidr_block
  public_subnet_ids     = module.vpc.public_subnet_ids
  certificate_arn       = var.certificate_arn
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  access_logs_bucket    = module.alb_logs_bucket.bucket_id
  waf_acl_arn           = var.waf_acl_arn
  deletion_protection   = var.deletion_protection
}

# ---------------- Data ----------------
module "rds" {
  source = "../../modules/rds"

  name                    = local.name
  vpc_id                  = module.vpc.vpc_id
  database_subnet_ids     = module.vpc.database_subnet_ids
  app_security_group_id   = module.app.security_group_id
  instance_class          = var.db_instance_class
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_days
  deletion_protection     = var.deletion_protection
  kms_key_arn             = module.kms.key_arn

  additional_ingress_security_group_ids = [module.eks.cluster_security_group_id]
}

# ---------------- Compute ----------------
module "app" {
  source = "../../modules/app-asg"

  name                  = local.name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr_block        = module.vpc.vpc_cidr_block
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
  instance_type         = var.instance_type
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity
  kms_key_arn           = module.kms.key_arn
  db_secret_arn         = module.rds.master_user_secret_arn
  user_data_base64      = base64encode(file("${path.module}/../../templates/user_data.sh"))
}

# ---------------- Kubernetes ----------------
module "eks" {
  source = "../../modules/eks"

  name                          = local.name
  kubernetes_version            = var.eks_version
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.private_subnet_ids
  kms_key_arn                   = module.kms.key_arn
  endpoint_public_access        = var.eks_endpoint_public_access
  endpoint_public_access_cidrs  = var.eks_endpoint_public_access_cidrs
  endpoint_private_access_cidrs = var.eks_endpoint_private_access_cidrs
  support_type                  = var.eks_support_type
  zonal_shift_enabled           = var.eks_zonal_shift_enabled
  deletion_protection           = var.deletion_protection
  log_retention_days            = var.log_retention_days
  admin_principal_arns          = var.eks_admin_principal_arns
  readonly_principal_arns       = var.eks_readonly_principal_arns
  node_groups                   = var.eks_node_groups
}
