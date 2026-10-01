variable "project"          {}
variable "alb_arn"          {}
variable "tg_blue_arn"      {}
variable "tg_green_arn"     {}
variable "blue_service"     {}
variable "green_service"    {}
variable "cluster_name"     {}
variable "alert_email"      { default = "" }

data "aws_region" "current" {}

locals {
  alb_suffix      = regex("app/.+", var.alb_arn)
  tg_blue_suffix  = regex("targetgroup/.+", var.tg_blue_arn)
  tg_green_suffix = regex("targetgroup/.+", var.tg_green_arn)
}

# ── SNS Topic ─────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Alarms ────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "blue_5xx" {
  alarm_name          = "${var.project}-blue-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  alarm_description   = "Blue target group 5xx rate above 5/min for 2 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = local.alb_suffix
    TargetGroup  = local.tg_blue_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "green_5xx" {
  alarm_name          = "${var.project}-green-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  alarm_description   = "Green target group 5xx rate above 5/min for 2 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = local.alb_suffix
    TargetGroup  = local.tg_green_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "blue_unhealthy" {
  alarm_name          = "${var.project}-blue-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Maximum"

  dimensions = {
    LoadBalancer = local.alb_suffix
    TargetGroup  = local.tg_blue_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "green_unhealthy" {
  alarm_name          = "${var.project}-green-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Maximum"

  dimensions = {
    LoadBalancer = local.alb_suffix
    TargetGroup  = local.tg_green_suffix
  }
}

# ── CloudWatch Dashboard ───────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-bluegreen"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
         y = 0
          width = 12
          height = 6
        properties = {
          title  = "Request Count by Target Group"
          period = 60
          region = data.aws_region.current.region
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_blue_suffix, { label = "Blue" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_green_suffix, { label = "Green" }]
          ]
        }
      },
      {
        type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
        properties = {
          title  = "5xx Errors by Target Group"
          period = 60
          region = data.aws_region.current.region
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_blue_suffix, { label = "Blue 5xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_green_suffix, { label = "Green 5xx" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y = 6
         width = 12
         height = 6
        properties = {
          title  = "Target Response Time (p95)"
          period = 60
          region = data.aws_region.current.region
          stat   = "p95"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_blue_suffix, { label = "Blue p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_green_suffix, { label = "Green p95" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
         y = 6
          width = 12
           height = 6
        properties = {
          title  = "Healthy Host Count"
          period = 60
          stat   = "Average"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_blue_suffix, { label = "Blue healthy" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", local.alb_suffix, "TargetGroup", local.tg_green_suffix, { label = "Green healthy" }]
          ]
        }
      }
    ]
  })
}

output "sns_topic_arn" { value = aws_sns_topic.alerts.arn }
