variable "project" { default = "bluegreen" }
variable "aws_region" { default = "us-east-1" }
variable "image_tag" {}
variable "alert_email" { default = "" }

# ── Network ───────────────────────────────────────────────────────────────────
module "network" {
  source     = "../../modules/network"
  project    = var.project
  aws_region = var.aws_region
}

# ── ALB + Target Groups ───────────────────────────────────────────────────────
module "alb" {
  source         = "../../modules/alb"
  project        = var.project
  vpc_id         = module.network.vpc_id
  public_subnets = module.network.public_subnets
}

# ── ECS Cluster (shared) ───────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-prod"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  ecr_repo = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com/${var.project}/app"
}

# ── Blue Environment ──────────────────────────────────────────────────────────
module "blue" {
  source           = "../../modules/ecs_env"
  project          = var.project
  color            = "blue"
  image_tag        = var.image_tag
  ecr_repo         = local.ecr_repo
  target_group_arn = module.alb.tg_blue_arn
  vpc_id           = module.network.vpc_id
  private_subnets  = module.network.private_subnets
  ecs_cluster_id   = aws_ecs_cluster.main.id
  ecs_sg_id        = module.alb.ecs_sg_id
}

# ── Green Environment ─────────────────────────────────────────────────────────
module "green" {
  source           = "../../modules/ecs_env"
  project          = var.project
  color            = "green"
  image_tag        = var.image_tag
  ecr_repo         = local.ecr_repo
  target_group_arn = module.alb.tg_green_arn
  vpc_id           = module.network.vpc_id
  private_subnets  = module.network.private_subnets
  ecs_cluster_id   = aws_ecs_cluster.main.id
  ecs_sg_id        = module.alb.ecs_sg_id
}

# ── Observability ─────────────────────────────────────────────────────────────
module "observability" {
  source        = "../../modules/observability"
  project       = var.project
  alb_arn       = module.alb.alb_arn
  tg_blue_arn   = module.alb.tg_blue_arn
  tg_green_arn  = module.alb.tg_green_arn
  blue_service  = module.blue.service_name
  green_service = module.green.service_name
  cluster_name  = aws_ecs_cluster.main.name
  alert_email   = var.alert_email
}

# ── Outputs (used by scripts and GitHub Actions) ───────────────────────────────
output "alb_dns_name" { value = module.alb.alb_dns_name }
output "prod_listener_arn" { value = module.alb.prod_listener_arn }
output "test_listener_arn" { value = module.alb.test_listener_arn }
output "tg_blue_arn" { value = module.alb.tg_blue_arn }
output "tg_green_arn" { value = module.alb.tg_green_arn }
output "blue_service_name" { value = module.blue.service_name }
output "green_service_name" { value = module.green.service_name }
output "ecs_cluster_name" { value = aws_ecs_cluster.main.name }
output "ecr_repo" { value = local.ecr_repo }
