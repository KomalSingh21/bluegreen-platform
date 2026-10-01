# ── ecs_env module ────────────────────────────────────────────────────────────
# Instantiated twice (blue + green). Only color, image_tag, and tg_arn differ.

variable "project"          {}
variable "color"            {}   # "blue" or "green"
variable "image_tag"        {}   # immutable ECR tag
variable "ecr_repo"         {}
variable "target_group_arn" {}
variable "vpc_id"           {}
variable "private_subnets"  {}
variable "ecs_cluster_id"   {}
variable "ecs_sg_id"        {}
variable "task_cpu"         { default = 256  }
variable "task_memory"      { default = 512  }
variable "desired_count"    { default = 1    }

# ── IAM ───────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project}-${var.color}-exec"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-${var.color}-task"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

# ── CloudWatch Log Group ───────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}/${var.color}"
  retention_in_days = 7
}

# ── Task Definition ───────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-${var.color}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = "app"
    image = "${var.ecr_repo}:${var.image_tag}"
    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    environment = [
      { name = "APP_VERSION", value = var.image_tag },
      { name = "COLOR",       value = var.color      },
      { name = "NODE_ENV",    value = "production"   }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "app"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/health || exit 1"]
      interval    = 10
      timeout     = 3
      retries     = 2
      startPeriod = 10
    }
  }])
}

data "aws_region" "current" {}

# ── ECS Service ───────────────────────────────────────────────────────────────
resource "aws_ecs_service" "app" {
  name            = "${var.project}-${var.color}"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = 3000
  }

  # Allow pipeline to change task definition without Terraform reverting it
  lifecycle {
    ignore_changes = [desired_count]
  }
}

output "service_name"        { value = aws_ecs_service.app.name }
output "task_definition_arn" { value = aws_ecs_task_definition.app.arn }
