# =============================================================================
# msk module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the broker ENIs (one per AZ)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups attached to the brokers."
  type        = list(string)
}

variable "broker_instance_type" {
  description = "EC2 instance type for brokers."
  type        = string
}

variable "broker_count" {
  description = "Number of broker nodes."
  type        = number
}

variable "ebs_volume_size" {
  description = "EBS volume size (GiB) per broker."
  type        = number
}

variable "kafka_version" {
  description = "Kafka version."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group for broker logs."
  type        = string
}

variable "dms_scram_username" {
  description = "SCRAM username the DMS producer uses to authenticate to MSK."
  type        = string
  default     = "dms-producer"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
