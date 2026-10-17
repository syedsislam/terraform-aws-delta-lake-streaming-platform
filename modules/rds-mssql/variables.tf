# =============================================================================
# rds-mssql module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the RDS instance."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups attached to the RDS instance."
  type        = list(string)
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
}

variable "engine_version" {
  description = "SQL Server engine version."
  type        = string
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment."
  type        = bool
}

variable "database_name" {
  description = "Name of the demo source database."
  type        = string
}

variable "master_username" {
  description = "Master username for the SQL Server instance."
  type        = string
  default     = "dbadmin"
}

variable "backup_retention_period" {
  description = "Backup retention in days (required > 0 for DMS CDC)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1
    error_message = "DMS CDC requires automated backups: retention must be >= 1 day."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from accidental terraform destroy."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
