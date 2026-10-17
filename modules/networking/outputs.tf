# =============================================================================
# networking module — outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the platform VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "msk_security_group_id" {
  description = "Security group for MSK brokers."
  value       = aws_security_group.msk.id
}

output "rds_security_group_id" {
  description = "Security group for RDS SQL Server."
  value       = aws_security_group.rds.id
}

output "dms_security_group_id" {
  description = "Security group for the DMS replication instance."
  value       = aws_security_group.dms.id
}

output "glue_security_group_id" {
  description = "Security group for Glue streaming job ENIs."
  value       = aws_security_group.glue.id
}

output "glue_connection_name" {
  description = "Name of the Glue NETWORK connection used by streaming jobs."
  value       = aws_glue_connection.vpc.name
}
