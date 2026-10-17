# =============================================================================
# glue-streaming module — outputs
# =============================================================================

output "job_names" {
  description = "Names of the bronze, silver and gold streaming jobs."
  value       = [for j in aws_glue_job.streaming : j.name]
}

output "job_arns" {
  description = "ARNs of the streaming jobs."
  value       = [for j in aws_glue_job.streaming : j.arn]
}

output "catalog_database_name" {
  description = "Glue Data Catalog database for the Delta tables."
  value       = aws_glue_catalog_database.lake.name
}

output "bronze_table_names" {
  description = "Catalog names of the bronze Delta tables."
  value       = [for k, t in aws_glue_catalog_table.layer_tables : t.name if startswith(k, "bronze_")]
}

output "silver_table_names" {
  description = "Catalog names of the silver Delta tables."
  value       = [for k, t in aws_glue_catalog_table.layer_tables : t.name if startswith(k, "silver_")]
}

output "gold_table_names" {
  description = "Catalog names of the gold Delta marts."
  value       = [for t in aws_glue_catalog_table.gold_marts : t.name]
}
