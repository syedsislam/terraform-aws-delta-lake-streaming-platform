# =============================================================================
# rds-mssql module — outputs
# =============================================================================

output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.sqlserver.id
}

output "db_endpoint" {
  description = "Connection endpoint (hostname) of the SQL Server instance."
  value       = aws_db_instance.sqlserver.address
  sensitive   = true
}

output "db_port" {
  description = "Port of the SQL Server instance."
  value       = aws_db_instance.sqlserver.port
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN holding the master credentials JSON."
  value       = aws_secretsmanager_secret.db_credentials.arn
  sensitive   = true
}

output "db_name" {
  description = "Name of the demo source database."
  value       = var.database_name
}
