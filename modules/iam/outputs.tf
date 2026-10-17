# =============================================================================
# iam module — outputs
# =============================================================================

output "glue_job_role_arn" {
  description = "ARN of the IAM role assumed by Glue streaming jobs."
  value       = aws_iam_role.glue_job.arn
}

output "dms_vpc_role_arn" {
  description = "ARN of the dms-vpc-role service role."
  value       = aws_iam_role.dms_vpc.arn
}

output "dms_cloudwatch_logs_role_arn" {
  description = "ARN of the dms-cloudwatch-logs-role service role."
  value       = aws_iam_role.dms_cloudwatch_logs.arn
}
