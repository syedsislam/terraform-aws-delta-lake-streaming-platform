# =============================================================================
# dms module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the replication instance."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups for the replication instance."
  type        = list(string)
}

variable "replication_instance_class" {
  description = "DMS replication instance class."
  type        = string
}

variable "engine_version" {
  description = "DMS replication engine version."
  type        = string
}

variable "source_secret_arn" {
  description = "Secrets Manager ARN with the SQL Server credentials JSON."
  type        = string
}

variable "source_endpoint_address" {
  description = "Hostname of the SQL Server source."
  type        = string
}

variable "source_endpoint_port" {
  description = "Port of the SQL Server source."
  type        = number
}

variable "source_database_name" {
  description = "Source database name on the SQL Server instance."
  type        = string
}

variable "kafka_bootstrap_brokers" {
  description = "MSK bootstrap brokers (SASL_SSL)."
  type        = string
  sensitive   = true
}

variable "kafka_sasl_username" {
  description = "SCRAM username for the DMS producer."
  type        = string
}

variable "kafka_sasl_password" {
  description = "SCRAM password for the DMS producer."
  type        = string
  sensitive   = true
}

variable "cdc_tables" {
  description = "Schema-qualified tables to replicate (schema.table)."
  type        = list(string)
}

variable "cdc_topic_prefix" {
  description = "Prefix for Kafka topics, e.g. sqlserver.cdc."
  type        = string
}

variable "vpc_role_arn" {
  description = "ARN of the dms-vpc-role IAM role."
  type        = string
}

variable "replication_task_start" {
  description = "Start the replication task on creation (disable for plan-only runs)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
