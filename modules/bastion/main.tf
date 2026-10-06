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

  tags = merge(var.tags, { Name = "${var.name}-bastion" })

  lifecycle {
    # A new AL2023 AMI shouldn't silently replace the box; bump deliberately.
    ignore_changes = [ami]
  }
}
