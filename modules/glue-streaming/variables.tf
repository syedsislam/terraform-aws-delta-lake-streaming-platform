# =============================================================================
# glue-streaming module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "glue_role_arn" {
  description = "IAM role assumed by the Glue streaming jobs."
  type        = string
}

variable "glue_connection" {
  description = "Name of the Glue NETWORK connection for VPC access."
  type        = string
}

variable "data_lake_bucket" {
  description = "S3 bucket holding the Delta Lake tables."
  type        = string
}

variable "scripts_bucket" {
  description = "S3 bucket holding the Glue job Python scripts."
  type        = string
}

variable "scripts_prefix" {
  description = "Prefix of the scripts inside the scripts bucket."
  type        = string
}

variable "kafka_bootstrap" {
  description = "MSK bootstrap brokers (IAM auth)."
  type        = string
  sensitive   = true
}

variable "cdc_topic_prefix" {
  description = "Kafka topic prefix, e.g. sqlserver.cdc."
  type        = string
}

variable "cdc_tables" {
  description = "Schema-qualified CDC tables (schema.table)."
  type        = list(string)
}

variable "worker_type" {
  description = "Glue worker type."
  type        = string
}

variable "number_of_workers" {
  description = "Number of workers per streaming job."
  type        = number
}

variable "glue_version" {
  description = "AWS Glue version."
  type        = string
}

variable "delta_spark_version" {
  description = "Delta Lake Spark connector version."
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
