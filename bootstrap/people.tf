# ======================= Human access =======================
# Pattern (no SSO on this account): IAM users hold NO permissions themselves.
# They can only manage their own credentials and, WITH MFA, assume a role.
#   platform-admins -> role/platform-admin     (AWS admin, EKS cluster-admin)
#   developers      -> role/developer-readonly (AWS view-only, EKS view, bastion tunnel only)
# Managed here (not by the CI apply role, which is denied iam:CreateUser by design).
# Passwords and access keys are NOT created by Terraform, so no secret lands in state:
# each person sets them up themselves, and nothing works until MFA is enabled.

locals {
  people = merge(
    { for u in var.admin_users : u => "platform-admins" },
    { for u in var.developer_users : u => "developers" },
  )
  cluster_arn_prefix = "arn:aws:eks:${var.region}:${var.aws_account_id}:cluster/${var.project}-${var.environment}"
}

resource "aws_iam_group" "platform_admins" {
  name = "platform-admins"
}

resource "aws_iam_group" "developers" {
  name = "developers"
}

resource "aws_iam_user" "this" {
  #checkov:skip=CKV_AWS_273:IAM Identity Center needs AWS Organizations, which upgrades this Free-plan account to paid. Users hold no permissions; access is MFA-gated role assumption.
  for_each = local.people

  name          = each.key
  force_destroy = true # lets Terraform remove a leaver even if they created keys / MFA
  tags          = { Team = each.value }
}

resource "aws_iam_user_group_membership" "this" {
  for_each = local.people

  user   = aws_iam_user.this[each.key].name
  groups = [each.value == "platform-admins" ? aws_iam_group.platform_admins.name : aws_iam_group.developers.name]
}

# ---------- Self-service + force MFA (attached to both groups) ----------
# Based on the AWS-documented "force MFA" policy: without MFA a user can only
# set up MFA and change their password; everything else is denied.
data "aws_iam_policy_document" "self_service_force_mfa" {
  statement {
    sid = "ViewAccountInfo"
    actions = [
      "iam:GetAccountPasswordPolicy",
      "iam:ListVirtualMFADevices",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageOwnPasswordKeysAndMFA"
    actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetLoginProfile",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
      "iam:GetAccessKeyLastUsed",
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:ListMFADevices",
      "iam:DeactivateMFADevice",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:user/$${aws:username}",
      "arn:aws:iam::${var.aws_account_id}:mfa/$${aws:username}",
    ]
  }

  statement {
    sid    = "DenyEverythingElseWithoutMFA"
    effect = "Deny"
    not_actions = [
      "iam:ChangePassword",
      "iam:GetUser",
      "iam:GetAccountPasswordPolicy",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "sts:GetSessionToken",
      # Long-term keys never carry aws:MultiFactorAuthPresent, so AssumeRole must be
      # exempt here; the ROLE trust policy is what enforces MFA for it.
      "sts:AssumeRole",
    ]
    resources = ["*"]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "self_service_force_mfa" {
  name        = "self-service-force-mfa"
  description = "Manage own credentials; deny everything else until MFA is used"
  policy      = data.aws_iam_policy_document.self_service_force_mfa.json
}

resource "aws_iam_group_policy_attachment" "self_service" {
  for_each = {
    admins     = aws_iam_group.platform_admins.name
    developers = aws_iam_group.developers.name
  }

  group      = each.value
  policy_arn = aws_iam_policy.self_service_force_mfa.arn
}

# Groups may assume exactly one role each (the role trust adds the MFA requirement).
resource "aws_iam_group_policy" "assume_admin" {
  name  = "assume-platform-admin"
  group = aws_iam_group.platform_admins.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.platform_admin.arn }]
  })
}

resource "aws_iam_group_policy" "assume_developer" {
  name  = "assume-developer-readonly"
  group = aws_iam_group.developers.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.developer.arn }]
  })
}

# ---------- Roles ----------
data "aws_iam_policy_document" "assume_with_mfa" {
  for_each = {
    admin     = var.admin_users
    developer = var.developer_users
  }

  statement {
    actions = ["sts:AssumeRole", "sts:SetSourceIdentity"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }
    # Only these specific users (checked by ARN, so the policy is valid before they exist).
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [for u in each.value : "arn:aws:iam::${var.aws_account_id}:user/${u}"]
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
    # MFA must be recent (1h) - a stolen long-lived session can't keep re-assuming.
    condition {
      test     = "NumericLessThan"
      variable = "aws:MultiFactorAuthAge"
      values   = ["3600"]
    }
  }
}

resource "aws_iam_role" "platform_admin" {
  name                 = "platform-admin"
  assume_role_policy   = data.aws_iam_policy_document.assume_with_mfa["admin"].json
  max_session_duration = 14400 # 4h
}

resource "aws_iam_role_policy_attachment" "platform_admin" {
  #checkov:skip=CKV_AWS_274:Human break-glass/admin role; requires named user + MFA < 1h, all actions in CloudTrail
  role       = aws_iam_role.platform_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "developer" {
  name                 = "developer-readonly"
  assume_role_policy   = data.aws_iam_policy_document.assume_with_mfa["developer"].json
  max_session_duration = 3600
}

# ViewOnlyAccess shows resources/config but NOT data (unlike ReadOnlyAccess,
# which can download S3 objects).
resource "aws_iam_role_policy_attachment" "developer_view" {
  role       = aws_iam_role.developer.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

data "aws_iam_policy_document" "developer_eks_tunnel" {
  statement {
    sid       = "DescribeClusterForKubeconfig"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = ["${local.cluster_arn_prefix}*"]
  }

  # Port-forward ONLY: the tunnel document is allowed, an interactive shell is not.
  statement {
    sid       = "TunnelDocumentOnly"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-StartPortForwardingSessionToRemoteHost"]
  }

  statement {
    sid       = "TunnelThroughBastionOnly"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${var.region}:${var.aws_account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Role"
      values   = ["bastion"]
    }
    # Forces SSM to check the document permission above (blocks the default shell).
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }
  }

  # Session Manager data is KMS-encrypted with the environment's platform key.
  statement {
    sid       = "SessionEncryption"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["arn:aws:kms:${var.region}:${var.aws_account_id}:key/*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = ["alias/${var.project}-${var.environment}"]
    }
  }

  statement {
    sid       = "ManageOwnSessions"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:aws:ssm:*:*:session/$${aws:userid}-*"]
  }
}

resource "aws_iam_role_policy" "developer_eks_tunnel" {
  name   = "eks-tunnel"
  role   = aws_iam_role.developer.id
  policy = data.aws_iam_policy_document.developer_eks_tunnel.json
}

# ---------- Account password policy ----------
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}
