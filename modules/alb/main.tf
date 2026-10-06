resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Ingress to the public ALB"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value} (redirected to HTTPS when a certificate is set)"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Egress only to the app port inside the VPC - not 0.0.0.0/0.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "To application targets"
  cidr_ipv4         = var.vpc_cidr_block
  from_port         = var.target_port
  to_port           = var.target_port
  ip_protocol       = "tcp"
}

resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_28:WAF is attached via var.waf_acl_arn (required for prod)
  #checkov:skip=CKV2_AWS_76:WAF rules (incl. Log4j AMR) live in the web ACL managed outside this module
  #checkov:skip=CKV_AWS_150:Driven by var.deletion_protection - true in qa/prod, false in dev for teardown
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60
  tags                       = var.tags

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.name
    enabled = true
  }
}

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB; ALB->target traffic stays inside the VPC on SG-restricted ports
  name_prefix          = substr(replace(var.name, "-", ""), 0, 6)
  port                 = var.target_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  tags                 = var.tags

  health_check {
    path                = var.health_check_path
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  https_enabled = var.certificate_arn != null
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Redirects to HTTPS whenever certificate_arn is set; plain HTTP only allowed in sandbox
  #checkov:skip=CKV_AWS_103:Same as above - TLS policy is enforced on the HTTPS listener
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # With a certificate: redirect to HTTPS. Without one (sandbox only): forward.
  default_action {
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.this.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf_acl_arn == null ? 0 : 1

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_acl_arn
}
