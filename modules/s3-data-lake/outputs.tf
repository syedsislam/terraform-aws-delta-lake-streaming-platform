# =============================================================================
# s3-data-lake module — outputs
# =============================================================================

output "data_lake_bucket" {
  description = "Name of the Delta Lake data bucket."
  value       = aws_s3_bucket.data_lake.id
}

output "data_lake_bucket_arn" {
  description = "ARN of the Delta Lake data bucket."
  value       = aws_s3_bucket.data_lake.arn
}

output "scripts_bucket" {
  description = "Name of the bucket holding the Glue job scripts."
  value       = aws_s3_bucket.scripts.id
}

output "scripts_prefix" {
  description = "Prefix of the Glue job scripts inside the scripts bucket."
  value       = "glue-jobs"
}

output "kms_key_arn" {
  description = "ARN of the KMS key encrypting the data lake."
  value       = aws_kms_key.lake.arn
}

output "zone_prefixes" {
  description = "Top-level data lake zones."
  value       = var.lake_prefixes
}
