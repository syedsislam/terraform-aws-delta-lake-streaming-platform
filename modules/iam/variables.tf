# =============================================================================
# iam module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
