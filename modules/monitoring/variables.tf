# =============================================================================
# monitoring module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "msk_cluster_name" {
  description = "MSK cluster name (CloudWatch dimension)."
  type        = string
}

variable "dms_replication_task_arn" {
  description = "ARN of the DMS replication task."
  type        = string
}

variable "glue_job_names" {
  description = "Names of the Glue streaming jobs to alarm on."
  type        = list(string)
}

variable "rds_instance_id" {
  description = "RDS instance identifier."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
}

variable "alarm_sns_topic_name" {
  description = "Name of the SNS topic for alarm notifications."
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
