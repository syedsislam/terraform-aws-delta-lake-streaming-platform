# =============================================================================
# Naming, tagging and shared conventions
#
# Every resource in this platform follows the same naming scheme:
#   <project>-<environment>-<component>
# and carries the same tag set, so cost allocation, ownership and
# environment are always traceable in the console, CLI and Cost Explorer.
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    },
    var.extra_tags
  )

  # Kafka topic naming convention: sqlserver.cdc.<schema>.<table>
  # The DMS replication task builds topics from this template.
  cdc_topic_prefix = "sqlserver.cdc"

  # S3 layout of the Delta Lake data lake
  lake_prefixes = ["bronze", "silver", "gold", "checkpoints", "_tmp"]
}
