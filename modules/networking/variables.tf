# =============================================================================
# networking module — inputs
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<environment>)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across."
  type        = list(string)
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private subnets can reach the internet (e.g. for DMS and Glue endpoints)."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create gateway/interface VPC endpoints for S3 and Glue so data-plane traffic stays off the public internet."
  type        = bool
  default     = true
}
