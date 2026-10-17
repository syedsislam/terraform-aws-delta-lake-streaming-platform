# =============================================================================
# Root module outputs — the integration surface other tooling consumes.
# =============================================================================

output "vpc_id" {
  description = "ID of the platform VPC."
  value       = module.networking.vpc_id
}

output "data_lake_bucket" {
  description = "S3 bucket holding the bronze/silver/gold Delta Lake tables."
  value       = module.s3_data_lake.data_lake_bucket
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster ingesting CDC events."
  value       = module.msk.cluster_arn
}

output "msk_bootstrap_brokers_iam" {
  description = "IAM-authenticated bootstrap brokers for MSK."
  value       = module.msk.bootstrap_brokers_iam
  sensitive   = true
}

output "rds_endpoint" {
  description = "Connection endpoint of the SQL Server source database."
  value       = module.rds_mssql.db_endpoint
  sensitive   = true
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN holding the SQL Server credentials."
  value       = module.rds_mssql.db_credentials_secret_arn
  sensitive   = true
}

output "dms_replication_task_arn" {
  description = "ARN of the DMS full-load + CDC replication task."
  value       = module.dms.replication_task_arn
}

output "glue_job_names" {
  description = "Names of the bronze, silver and gold Glue streaming jobs."
  value       = module.glue_streaming.job_names
}

output "glue_catalog_database" {
  description = "Glue Data Catalog database registering the Delta tables."
  value       = module.glue_streaming.catalog_database_name
}

output "alarm_sns_topic_arn" {
  description = "SNS topic receiving CloudWatch alarm notifications."
  value       = module.monitoring.alarm_topic_arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard for the streaming platform."
  value       = module.monitoring.dashboard_name
}
