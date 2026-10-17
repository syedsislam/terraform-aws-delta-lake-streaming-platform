# =============================================================================
# dms module — outputs
# =============================================================================

output "replication_instance_arn" {
  description = "ARN of the DMS replication instance."
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_task_arn" {
  description = "ARN of the full-load + CDC replication task."
  value       = aws_dms_replication_task.cdc.replication_task_arn
}

output "source_endpoint_arn" {
  description = "ARN of the SQL Server source endpoint."
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "target_endpoint_arn" {
  description = "ARN of the MSK target endpoint."
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "cdc_topics" {
  description = "Kafka topics the CDC tables are replicated to."
  value       = [for t in var.cdc_tables : "${var.cdc_topic_prefix}.${t}"]
}
