data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_root = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
}

data "aws_iam_policy_document" "this" {
  #checkov:skip=CKV_AWS_109:Key policy - Resource "*" means "this key" only
  #checkov:skip=CKV_AWS_111:Key policy - Resource "*" means "this key" only
  #checkov:skip=CKV_AWS_356:Key policy - Resource "*" means "this key" only
  # Root account keeps full control so the key can never become unmanageable.
  statement {
    sid       = "EnableRootAccountPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  # CloudWatch Logs needs explicit grant to encrypt log groups (VPC flow logs).
  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  # EC2 Auto Scaling service-linked role must use the key for encrypted EBS volumes.
  # Matched by condition (not principal) because in a fresh account the SLR does not
  # exist until the first ASG is created, and KMS rejects policies with unknown principals.
  dynamic "statement" {
    for_each = var.allow_autoscaling_service_role ? [1] : []
    content {
      sid = "AllowAutoScalingServiceLinkedRole"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
      condition {
        test     = "ArnEquals"
        variable = "aws:PrincipalArn"
        values   = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  #checkov:skip=CKV_AWS_33:Wildcard principal is constrained by aws:PrincipalArn to the AutoScaling SLR
  description             = var.description
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.this.json
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
