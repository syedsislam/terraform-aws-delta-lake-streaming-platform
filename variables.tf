# =============================================================================
# Root module input variables
# =============================================================================

variable "project" {
  description = "Project name used as the prefix for all resource names and tags."
  type        = string
  default     = "delta-stream"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project))
    error_message = "Project must be 3-32 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Drives naming, tagging and sizing."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like a valid AWS region (e.g. us-east-1)."
  }
}

variable "owner" {
  description = "Owner tag applied to every resource (e.g. team name or email)."
  type        = string
}

variable "cost_center" {
  description = "Cost center tag applied to every resource for chargeback."
  type        = string
  default     = "data-platform"
}

variable "extra_tags" {
  description = "Additional tags merged into the common tag set."
  type        = map(string)
  default     = {}
}

# --- Networking ----------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "AZs to spread subnets across (must match the region)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two AZs are required for MSK and RDS Multi-AZ."
  }
}

# --- MSK -----------------------------------------------------------------------

variable "msk_broker_instance_type" {
  description = "EC2 instance type for MSK brokers."
  type        = string
  default     = "kafka.m5.large"
}

variable "msk_broker_count" {
  description = "Number of MSK broker nodes (one per AZ)."
  type        = number
  default     = 3

  validation {
    condition     = var.msk_broker_count >= 2 && var.msk_broker_count <= 15
    error_message = "MSK broker count must be between 2 and 15."
  }
}

variable "msk_ebs_volume_size" {
  description = "EBS volume size (GiB) per MSK broker."
  type        = number
  default     = 100

  validation {
    condition     = var.msk_ebs_volume_size >= 10
    error_message = "MSK EBS volume size must be at least 10 GiB."
  }
}

variable "kafka_version" {
  description = "Kafka version for the MSK cluster."
  type        = string
  default     = "3.7.x"
}

# --- RDS SQL Server --------------------------------------------------------------

variable "rds_instance_class" {
  description = "RDS instance class for the SQL Server source database."
  type        = string
  default     = "db.m5.large"
}

variable "rds_allocated_storage" {
  description = "Allocated storage (GiB) for the RDS SQL Server instance."
  type        = number
  default     = 100

  validation {
    condition     = var.rds_allocated_storage >= 20
    error_message = "RDS SQL Server requires at least 20 GiB of storage."
  }
}

variable "rds_engine_version" {
  description = "SQL Server engine version for RDS."
  type        = string
  default     = "15.00.4435.7.v1" # SQL Server 2019
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for the RDS SQL Server instance."
  type        = bool
  default     = true
}

variable "source_database_name" {
  description = "Name of the demo source database on the SQL Server instance."
  type        = string
  default     = "salesdb"
}

# Tables replicated via CDC, as schema-qualified names. DMS builds one Kafka
# topic per table following sqlserver.cdc.<schema>.<table>.
variable "cdc_tables" {
  description = "Schema-qualified tables to replicate via CDC (schema.table)."
  type        = list(string)
  default     = ["dbo.orders", "dbo.customers", "dbo.products"]

  validation {
    condition     = length(var.cdc_tables) > 0 && alltrue([for t in var.cdc_tables : can(regex("^[A-Za-z0-9_]+\\.[A-Za-z0-9_]+$", t))])
    error_message = "Each CDC table must be in schema.table format."
  }
}

# --- DMS -------------------------------------------------------------------------

variable "dms_instance_class" {
  description = "DMS replication instance class."
  type        = string
  default     = "dms.c5.large"

  validation {
    condition     = can(regex("^dms\\.", var.dms_instance_class))
    error_message = "DMS instance class must start with dms."
  }
}

variable "dms_engine_version" {
  description = "DMS replication engine version."
  type        = string
  default     = "3.5.3"
}

# --- Glue ------------------------------------------------------------------------

variable "glue_worker_type" {
  description = "Glue worker type for the streaming jobs."
  type        = string
  default     = "G.1X"

  validation {
    condition     = contains(["G.1X", "G.2X", "G.4X", "G.8X"], var.glue_worker_type)
    error_message = "Glue worker type must be one of G.1X, G.2X, G.4X, G.8X."
  }
}

variable "glue_workers" {
  description = "Number of workers per Glue streaming job."
  type        = number
  default     = 4

  validation {
    condition     = var.glue_workers >= 2
    error_message = "Streaming jobs need at least 2 workers for checkpoint reliability."
  }
}

variable "glue_version" {
  description = "AWS Glue version (4.0+ required for Spark 3.3 / Delta Lake)."
  type        = string
  default     = "4.0"
}

variable "delta_spark_version" {
  description = "Delta Lake Spark connector version (must match the Glue/Spark version; 2.4.0 targets Spark 3.3 / Glue 4.0)."
  type        = string
  default     = "2.4.0"
}

# --- Data lake -------------------------------------------------------------------

variable "data_lake_bucket_name" {
  description = "Globally-unique S3 bucket name for the Delta Lake data lake. If empty, a name is generated."
  type        = string
  default     = ""
}

variable "bronze_retention_days" {
  description = "Days before bronze objects transition to cheaper storage."
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "CloudWatch log retention for Glue/DMS/MSK logs (days)."
  type        = number
  default     = 30
}
