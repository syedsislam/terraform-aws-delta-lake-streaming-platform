# =============================================================================
# s3-data-lake module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "bucket_name_override" {
  description = "Override the generated data lake bucket name (must be globally unique)."
  type        = string
  default     = ""
}

variable "bronze_retention_days" {
  description = "Days before bronze objects transition to STANDARD_IA."
  type        = number
}

variable "lake_prefixes" {
  description = "Top-level prefixes (zones) of the data lake."
  type        = list(string)
  default     = ["bronze", "silver", "gold", "checkpoints", "_tmp"]
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
