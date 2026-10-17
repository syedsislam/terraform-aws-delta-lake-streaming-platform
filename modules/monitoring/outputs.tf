# =============================================================================
# monitoring module — outputs
# =============================================================================

output "msk_log_group_name" {
  description = "CloudWatch log group for MSK broker logs."
  value       = aws_cloudwatch_log_group.msk.name
}

output "alarm_topic_arn" {
  description = "SNS topic ARN for alarm notifications."
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = aws_cloudwatch_dashboard.pipeline.dashboard_name
}
