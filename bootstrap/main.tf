locals {
  repo         = "${var.github_org}/${var.github_repo}"
  state_bucket = "${var.project}-tfstate-${var.aws_account_id}-${var.region}"
  oidc_url     = "token.actions.githubusercontent.com"
  plan_role    = "gha-terraform-plan-${var.environment}"
  apply_role   = "gha-terraform-apply-${var.environment}"
}

# ======================= Remote state =======================
module "state_kms" {
  source = "../modules/kms"

  alias                   = "terraform-state"
  description             = "Encrypts Terraform state for ${var.environment}"
  deletion_window_in_days = 30
}

module "state_bucket" {
  source = "../modules/s3-bucket"

  bucket_name                        = local.state_bucket
  kms_key_arn                        = module.state_kms.key_arn
  force_destroy                      = false
  noncurrent_version_expiration_days = 365 # long history = easy state rollback
}

# ======================= GitHub OIDC =======================
# No long-lived AWS keys in GitHub. Workflows exchange a short-lived OIDC token for STS creds.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

# ---------- PLAN role: read-only, usable from PRs and main ----------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_url}:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = local.plan_role
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "ReadState"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [module.state_bucket.bucket_arn, "${module.state_bucket.bucket_arn}/*"]
  }

  # Plan only needs to create/delete the lock file, never overwrite state.
  statement {
    sid       = "ManageLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.state_bucket.bucket_arn}/*.tflock"]
  }

  statement {
    sid       = "StateKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [module.state_kms.key_arn]
  }

  # ReadOnlyAccess can read secrets metadata; block secret values explicitly.
  statement {
    sid       = "DenySecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

# ---------- APPLY role: only from the protected GitHub Environment ----------
# The sub claim "environment:<env>" is only issued to jobs that passed the
# environment's protection rules (required reviewers, branch restriction).
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["repo:${local.repo}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = local.apply_role
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

# Broad permissions are needed to manage infra, so we fence them with explicit denies.
# In a mature org, swap AdministratorAccess for a scoped policy + permissions boundary,
# and enforce the same guardrails as SCPs at the AWS Organizations level.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  #checkov:skip=CKV_AWS_274:Infra deployer needs broad rights; fenced by apply_guardrails deny policy + env approval gate
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "apply_guardrails" {
  statement {
    sid    = "ProtectCIIdentity"
    effect = "Deny"
    actions = [
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:DeleteRole",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/gha-terraform-*",
    ]
  }

  statement {
    sid    = "ProtectOIDCProvider"
    effect = "Deny"
    actions = [
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
    ]
    resources = [aws_iam_openid_connect_provider.github.arn]
  }

  statement {
    sid    = "ProtectStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketPublicAccessBlock",
    ]
    resources = [module.state_bucket.bucket_arn]
  }

  statement {
    sid       = "ProtectStateKey"
    effect    = "Deny"
    actions   = ["kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy"]
    resources = [module.state_kms.key_arn]
  }

  # Humans log in through SSO; CI must never mint long-lived credentials.
  statement {
    sid    = "NoLongLivedCredentials"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NoAccountOrOrgChanges"
    effect    = "Deny"
    actions   = ["organizations:*", "account:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_guardrails.json
}

# ======================= Cost guardrail =======================
resource "aws_budgets_budget" "monthly" {
  count = var.budget_email == null ? 0 : 1

  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 80]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
