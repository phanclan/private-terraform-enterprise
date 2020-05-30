# TFE Production External Services Module
#------------------------------------------------------------------------------
# AUTO SCALING
#------------------------------------------------------------------------------
resource "aws_launch_template" "tfe_lt" {
  name          = "${var.namespace}-tfe-ec2-asg-lt-primary"
  image_id      = data.aws_ami.tfe_ubuntu.id
  instance_type = var.aws_instance_type
  key_name      = var.ssh_key_name
  user_data     = var.user_data


  instance_market_options {
    market_type = "spot"

    spot_options {
      spot_instance_type = "one-time"
      max_price = "0.085"
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.tfe.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 40
    }
  }

  vpc_security_group_ids = [
    var.vpc_security_group_ids
  ]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      { Name = "${var.namespace}-tfe-ec2-primary" },
      { Type = "autoscaling-group" },
      var.common_tags
    )
  }

  tags = merge(
    { Name = "${var.namespace}-tfe-ec2-launch-template" },
     var.common_tags
  )
}

resource "aws_autoscaling_group" "tfe_asg" {
  name                      = "${var.namespace}-tfe-asg"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = var.tfe_subnet_ids
  health_check_grace_period = 15
  health_check_type         = "ELB"

  launch_template {
    id      = aws_launch_template.tfe_lt.id
    version = "$Latest"
  }
  target_group_arns = [
    aws_lb_target_group.tfe_443.arn,
    aws_lb_target_group.tfe_8800.arn
  ]
}

#------------------------------------------------------------------------------
# EC2 instances
#------------------------------------------------------------------------------

# resource "aws_instance" "primary" {
#   count                       = 1
#   # ami                         = var.aws_instance_ami
#   ami                         = data.aws_ami.tfe_ubuntu.id
#   instance_type               = var.aws_instance_type
#   subnet_id                   = var.tfe_subnet_ids[0]
#   vpc_security_group_ids      = [var.vpc_security_group_ids]
#   key_name                    = var.ssh_key_name
#   user_data                   = var.user_data
#   iam_instance_profile        = aws_iam_instance_profile.tfe.name
#   associate_public_ip_address = var.public_ip

#   root_block_device {
#     volume_size = 50
#     volume_type = "gp2"
#   }

#   tags = merge(
#     {
#       Name  = "${var.namespace}-tfe-instance-1"
#     },
#     var.common_tags,
#   )
# }

# resource "null_resource" "delay_secondary" {
#   count = var.create_second_instance

#   provisioner "local-exec" {
#     command = "sleep 300"
#   }

#   depends_on = [aws_instance.primary]
# }

# resource "aws_instance" "secondary" {
#   count                       = var.create_second_instance
#   ami                         = data.aws_ami.tfe_ubuntu.id
#   instance_type               = var.aws_instance_type
#   subnet_id                   = element(var.tfe_subnet_ids, count.index)
#   vpc_security_group_ids      = [var.vpc_security_group_ids]
#   key_name                    = var.ssh_key_name
#   user_data                   = var.user_data
#   iam_instance_profile        = aws_iam_instance_profile.tfe.name
#   associate_public_ip_address = var.public_ip

#   root_block_device {
#     volume_size = 50
#     volume_type = "gp2"
#   }

#   tags = merge(
#     {
#       Name  = "${var.namespace}-tags-instance-2"
#     },
#     var.common_tags,
#   )


#   depends_on = [null_resource.delay_secondary]
# }

### Routing resources

# Always create a certificate, but use fake domain if
# var.ssl_certificate_arn not blank.
# This is needed to enable conditional in listeners
# Since conditionals in TF 0.11 evaluate both possibilities
resource "aws_acm_certificate" "cert" {
  domain_name       = var.ssl_certificate_arn == "" ? var.hostname : format("fake-%s", var.hostname)
  validation_method = "DNS"
}

# This allows ACM to validate the new certificate
resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  zone_id = var.zone_id
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

# This allows ACM to validate the new certificate
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

resource "aws_route53_record" "pes" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "A"

  alias {
    name                   = aws_lb.tfe.dns_name
    zone_id                = aws_lb.tfe.zone_id
    evaluate_target_health = false
  }
}

#------------------------------------------------------------------------------
# LOAD BALANCING
#------------------------------------------------------------------------------

resource "aws_lb" "tfe" {
  name               = "${var.namespace}-alb"
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [var.vpc_security_group_ids]

  subnets            = var.alb_subnet_ids
  tags = {
    owner = var.owner
  }
}

resource "aws_lb_target_group" "tfe_443" {
  name        = "${var.namespace}-alb-tg-443"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  # target_type = "instance"

  health_check {
    path     = "/_health_check"
    protocol = "HTTPS"
    matcher  = "200"
    healthy_threshold   = 3 # Smaller than default to speed up
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15 # Smaller than default to speed up
  }

  tags = {
    owner = var.owner
  }
}

resource "aws_lb_target_group" "tfe_8800" {
  name        = "${var.namespace}-alb-tg-8800"
  port        = 8800
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  # target_type = "instance"

  health_check {
    path     = "/authenticate"
    protocol = "HTTPS"
    matcher  = "200"
  }

  tags = {
    owner = var.owner
  }
}

resource "aws_lb_listener" "tfe-443" {
  load_balancer_arn = aws_lb.tfe.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn == "" ? aws_acm_certificate.cert.arn : var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tfe_443.arn
  }

  depends_on = [aws_acm_certificate_validation.cert]
}

resource "aws_lb_listener" "tfe-8800" {
  load_balancer_arn = aws_lb.tfe.arn
  port              = "8800"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn == "" ? aws_acm_certificate.cert.arn : var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tfe_8800.arn
  }

  depends_on = [aws_acm_certificate_validation.cert]
}

#---
# [pp] Comment out next two resources if using ASG instead of Instances.
#---
# resource "aws_lb_target_group_attachment" "tfe_443" {
#   target_group_arn = aws_lb_target_group.tfe_443.arn
#   target_id        = aws_instance.primary[0].id
#   port             = 443
# }

# resource "aws_lb_target_group_attachment" "tfe_8800" {
#   target_group_arn = aws_lb_target_group.tfe_8800.arn
#   target_id        = aws_instance.primary[0].id
#   port             = 8800
# }

#------------------------------------------------------------------------------
# S3
#------------------------------------------------------------------------------

data "aws_kms_key" "s3" {
  key_id = var.kms_key_id
}

resource "aws_s3_bucket" "pes" {
  bucket        = var.tfe_bucket_name
  acl           = "private"
  force_destroy = true # [pp] Might not want this for PROD

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = data.aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  tags = merge(
    {
      Name = var.tfe_bucket_name
    },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# IAM resources
#------------------------------------------------------------------------------

resource "aws_iam_role" "tfe" {
  name = "${var.namespace}-tfe-iam-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Effect": "Allow"
    }
  ]
}
EOF

  tags = merge({ Name = "${var.namespace}-tfe-iam-role" }, var.common_tags)
}

resource "aws_iam_instance_profile" "tfe" {
  name = "${var.namespace}-tfe-iam-instance-profile"
  role = aws_iam_role.tfe.name
}

data "aws_iam_policy_document" "tfe" {
  statement {
    sid    = "AllowS3"
    effect = "Allow"

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.pes.id}",
      "arn:aws:s3:::${aws_s3_bucket.pes.id}/*",
      "arn:aws:s3:::${var.source_bucket_id}",
      "arn:aws:s3:::${var.source_bucket_id}/*",
    ]

    actions = [
      "s3:*",
    ]
  }

  statement {
    sid    = "AllowKMS"
    effect = "Allow"

    resources = [
      data.aws_kms_key.s3.arn,
    ]

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:DescribeKey",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
    ]
  }
}

resource "aws_iam_role_policy" "tfe" {
  name   = "${var.namespace}-tfe-iam-role-policy"
  role   = aws_iam_role.tfe.name
  policy = data.aws_iam_policy_document.tfe.json
}
