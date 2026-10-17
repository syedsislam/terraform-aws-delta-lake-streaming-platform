# =============================================================================
# msk module — outputs
# =============================================================================

output "cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.main.arn
}

output "cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.main.cluster_name
}

output "bootstrap_brokers_iam" {
  description = "Comma-separated IAM-authenticated bootstrap brokers."
  value       = aws_msk_cluster.main.bootstrap_brokers_sasl_iam
  sensitive   = true
}

output "bootstrap_brokers_tls" {
  description = "Comma-separated TLS bootstrap brokers."
  value       = aws_msk_cluster.main.bootstrap_brokers_tls
  sensitive   = true
}

output "bootstrap_brokers_sasl_scram" {
  description = "Comma-separated SASL/SCRAM bootstrap brokers (for the DMS producer)."
  value       = aws_msk_cluster.main.bootstrap_brokers_sasl_scram
  sensitive   = true
}

output "zookeeper_connect_string" {
  description = "ZooKeeper connection string."
  value       = aws_msk_cluster.main.zookeeper_connect_string
  sensitive   = true
}

output "dms_scram_username" {
  description = "SCRAM username for the DMS producer."
  value       = var.dms_scram_username
}

output "dms_scram_password" {
  description = "SCRAM password for the DMS producer."
  value       = random_password.dms_scram.result
  sensitive   = true
}

output "dms_scram_secret_arn" {
  description = "Secrets Manager ARN holding the DMS SCRAM credentials."
  value       = aws_secretsmanager_secret.dms_scram.arn
  sensitive   = true
}
