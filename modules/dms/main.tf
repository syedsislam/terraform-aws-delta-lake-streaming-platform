# =============================================================================
# dms module
#
# AWS DMS moves data in two phases:
#   1. Full load  — existing rows are bulk-copied to MSK topics.
#   2. Ongoing CDC — SQL Server CDC capture tables are tailed and every
#      insert/update/delete is streamed as a JSON event.
#
# Target topics follow sqlserver.cdc.<schema>.<table> via transformation rules
# in the table-mapping JSON below.
# =============================================================================

locals {
  # One selection rule per table: replicate exactly the tables in var.cdc_tables.
  selection_rules = [
    for idx, table in var.cdc_tables : {
      rule-type   = "selection"
      rule-id     = idx + 1
      rule-name   = idx + 1
      object-locator = {
        schema-name = split(".", table)[0]
        table-name  = split(".", table)[1]
      }
      rule-action = "include"
    }
  ]

  # Rename each table to its Kafka topic: sqlserver.cdc.<schema>.<table>.
  # For Kafka targets, a table-level "rename" transformation sets the topic
  # name, keeping producers and consumers on one explicit contract.
  topic_rules = [
    for idx, table in var.cdc_tables : {
      rule-type   = "transformation"
      rule-id     = 100 + idx + 1
      rule-name   = 100 + idx + 1
      rule-target = "table"
      object-locator = {
        schema-name = split(".", table)[0]
        table-name  = split(".", table)[1]
      }
      rule-action = "rename"
      value       = "${var.cdc_topic_prefix}.${table}"
    }
  ]

  table_mappings = jsonencode({
    rules = concat(local.selection_rules, local.topic_rules)
  })
}

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "${var.name_prefix}-dms-subnets"
  replication_subnet_group_description = "Private subnets for ${var.name_prefix} DMS"
  subnet_ids                           = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-dms-subnets" })
}

resource "aws_dms_replication_instance" "main" {
  replication_instance_id     = "${var.name_prefix}-dms"
  replication_instance_class  = var.replication_instance_class
  engine_version              = var.engine_version
  allocated_storage           = 100
  multi_az                    = true
  publicly_accessible         = false
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids      = var.security_group_ids
  apply_immediately           = true
  auto_minor_version_upgrade  = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-dms" })

  # NOTE: the AWS-managed DMS service roles (dms-vpc-role, dms-cloudwatch-logs-role)
  # must exist before this instance is created. Ordering is enforced in the root
  # module (module.dms depends_on module.iam), since depends_on cannot reference
  # plain string variables.
}

# --- Source: SQL Server (credentials via Secrets Manager, never in config) -----

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.name_prefix}-sqlserver-src"
  endpoint_type = "source"
  engine_name   = "sqlserver"

  server_name = var.source_endpoint_address
  port        = var.source_endpoint_port
  database_name = var.source_database_name
  ssl_mode    = "require"

  secrets_manager_access_role_arn = var.vpc_role_arn
  secrets_manager_secret_id       = var.source_secret_arn

  tags = merge(var.tags, { Name = "${var.name_prefix}-sqlserver-src" })
}

# --- Target: MSK (Kafka) --------------------------------------------------------
# SASL_SSL with SCRAM. AWS DMS Kafka targets do NOT support MSK IAM access
# control (documented limitation), so the DMS producer authenticates with the
# SCRAM credentials provisioned by the msk module. Glue consumers use IAM.

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.name_prefix}-msk-target"
  endpoint_type = "target"
  engine_name   = "kafka"

  kafka_settings {
    broker                         = var.kafka_bootstrap_brokers
    topic                          = "${var.cdc_topic_prefix}.default"
    message_format                 = "json"
    include_transaction_details    = false
    include_partition_value        = true
    partition_include_schema_table = true
    security_protocol              = "sasl-ssl"
    sasl_username                  = var.kafka_sasl_username
    sasl_password                  = var.kafka_sasl_password
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-msk-target" })
}

# --- Replication task: full load + ongoing CDC ----------------------------------

resource "aws_dms_replication_task" "cdc" {
  replication_task_id      = "${var.name_prefix}-sqlserver-to-msk"
  migration_type           = "full-load-and-cdc"
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  table_mappings           = local.table_mappings

  replication_task_settings = jsonencode({
    TargetMetadata = {
      SupportLobs = true
    }
    Logging = {
      EnableLogging = true
    }
    ChangeProcessingTuning = {
      BatchApplyEnabled = true
    }
  })

  # Test the endpoints before the task starts; fail fast on bad connectivity.
  start_replication_task = var.replication_task_start

  tags = merge(var.tags, { Name = "${var.name_prefix}-sqlserver-to-msk" })
}
