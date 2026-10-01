variable "project"         {}
variable "vpc_id"          {}
variable "public_subnets"  {}

# ── Security Groups ────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name   = "${var.project}-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Test listener — restrict to your CI runner or VPN in production
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # tighten this in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name   = "${var.project}-ecs-tasks-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-ecs-sg" }
}

# ── ALB ───────────────────────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = false
  tags = { Name = "${var.project}-alb" }
}

# ── Target Groups ─────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "blue" {
  name        = "${var.project}-tg-blue"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }

  deregistration_delay = 30   # fast draining for quick rollback

  tags = { Name = "${var.project}-tg-blue", Color = "blue" }
}

resource "aws_lb_target_group" "green" {
  name        = "${var.project}-tg-green"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = { Name = "${var.project}-tg-green", Color = "green" }
}

# ── Listeners ─────────────────────────────────────────────────────────────────
# PROD listener — pipeline owns this after first deploy; ignore_changes prevents drift
resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = 0
      }
    }
  }

  lifecycle {
    # Pipeline updates this; Terraform should not revert it on next apply
    ignore_changes = [default_action]
  }
}

# TEST listener — always points to the idle environment for smoke testing
# Initially points to green (blue is active by default)
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8443
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "alb_dns_name"       { value = aws_lb.main.dns_name }
output "alb_arn"            { value = aws_lb.main.arn }
output "prod_listener_arn"  { value = aws_lb_listener.prod.arn }
output "test_listener_arn"  { value = aws_lb_listener.test.arn }
output "tg_blue_arn"        { value = aws_lb_target_group.blue.arn }
output "tg_green_arn"       { value = aws_lb_target_group.green.arn }
output "ecs_sg_id"          { value = aws_security_group.ecs_tasks.id }
