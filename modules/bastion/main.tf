data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# No ingress at all: access is via SSM Session Manager (IAM-authenticated, logged),
# so there is no port 22, no key pair and no public IP to attack.
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-bastion-"
  description = "EKS bastion - egress only, access via SSM"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-bastion" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to EKS API, SSM, ECR and package repos"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ---------- IAM ----------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.name}-bastion-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Only what `aws eks update-kubeconfig` needs. Kubernetes permissions come from the
# EKS access entry for this role, not from IAM.
data "aws_iam_policy_document" "eks" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }
  statement {
    actions   = ["eks:ListClusters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eks" {
  name   = "eks-describe"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.eks.json
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.name}-bastion-"
  role        = aws_iam_role.this.name
  tags        = var.tags
}

# ---------- Instance ----------
resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    cluster_name       = var.cluster_name
    region             = data.aws_region.current.region
    kubernetes_version = var.kubernetes_version
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 30 # AL2023 AMI minimum; within the 30 GiB free-tier EBS allowance
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  # Role=bastion is what developer tunnel permissions are scoped to.
  tags = merge(var.tags, { Name = "${var.name}-bastion", Role = "bastion" })

  lifecycle {
    # A new AL2023 AMI shouldn't silently replace the box; bump deliberately.
    ignore_changes = [ami]
  }
}

# ---------- Session recording ----------
# Every interactive shell on the bastion is streamed to an encrypted log group.
# (Port-forward tunnels carry TLS to the EKS API and are not recorded; the EKS audit
# log records what was done, attributed to the person's own role.)
resource "aws_cloudwatch_log_group" "sessions" {
  count = var.session_logging ? 1 : 0

  #checkov:skip=CKV_AWS_338:Retention is per-environment
  name              = "/aws/ssm/sessions/${var.name}"
  retention_in_days = var.session_log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# Account/region-wide Session Manager preferences (one per account; one env per account).
resource "aws_ssm_document" "session_preferences" {
  count = var.session_logging ? 1 : 0

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: recorded, time-limited sessions"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions[0].name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = var.kms_key_arn # session data KMS-encrypted on top of TLS
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile                = { linux = "", windows = "" }
    }
  })
  tags = var.tags
}

data "aws_iam_policy_document" "session_logs" {
  count = var.session_logging ? 1 : 0

  # Instance side of KMS-encrypted Session Manager data.
  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.sessions[0].arn}:*"]
  }
  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "session_logs" {
  count = var.session_logging ? 1 : 0

  name   = "session-logs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.session_logs[0].json
}
