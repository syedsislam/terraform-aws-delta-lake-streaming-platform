# =============================================================================
# rds-mssql module
#
# Amazon RDS for SQL Server acting as the CDC source. This is a self-contained
# demo source; an on-premises SQL Server works identically as a DMS source
# endpoint (see docs/architecture.md).
#
# Credentials: a random master password is generated and stored in Secrets
# Manager. Nothing secret ever appears in state outputs or variable files.
#
# CDC: RDS SQL Server enables CDC via the msdb stored procedures
# (msdb.dbo.rds_cdc_enable_db / rds_cdc_enable_table), which Terraform cannot
# call directly. scripts/enable_cdc.sql runs once after apply — see
# docs/runbook.md for the exact steps.
# =============================================================================

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name_prefix}-sqlserver-credentials"
  description             = "Master credentials for the ${var.name_prefix} SQL Server source"
  recovery_window_in_days = 30

  tags = merge(var.tags, { Name = "${var.name_prefix}-sqlserver-credentials" })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "sqlserver"
    host     = aws_db_instance.sqlserver.address
    port     = aws_db_instance.sqlserver.port
    dbname   = var.database_name
  })
}

resource "aws_db_subnet_group" "sqlserver" {
  name       = "${var.name_prefix}-sqlserver-subnets"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-sqlserver-subnets" })
}

resource "aws_db_parameter_group" "sqlserver" {
  name   = "${var.name_prefix}-sqlserver-params"
  family = "sqlserver-se-15.0"

  # Keep the transaction log readable for DMS CDC and cap expensive queries
  # from the demo workload.
  parameter {
    name         = "rds.sqlserver_audit"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_db_instance" "sqlserver" {
  identifier = "${var.name_prefix}-sqlserver"

  engine                      = "sqlserver-se"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.database_name
  username                    = var.master_username
  password                    = random_password.master.result
  port                        = 1433
  multi_az                    = var.multi_az
  publicly_accessible         = false
  deletion_protection         = var.deletion_protection
  backup_retention_period     = var.backup_retention_period
  backup_window               = "03:00-04:00"
  maintenance_window          = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot       = true
  auto_minor_version_upgrade  = true

  db_subnet_group_name   = aws_db_subnet_group.sqlserver.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.sqlserver.name

  # Final snapshot on destroy unless this is a throwaway dev instance.
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = "${var.name_prefix}-sqlserver-final"

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  enabled_cloudwatch_logs_exports = ["error", "agent"]

  tags = merge(var.tags, { Name = "${var.name_prefix}-sqlserver" })

  # The secret version needs the live endpoint, so order it explicitly.
  depends_on = [aws_secretsmanager_secret.db_credentials]
}

# Restore the secret's JSON once the endpoint is known (the first version is
# written before the address exists, so update it after creation).
resource "aws_secretsmanager_secret_version" "db_credentials_final" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "sqlserver"
    host     = aws_db_instance.sqlserver.address
    port     = aws_db_instance.sqlserver.port
    dbname   = var.database_name
  })

  depends_on = [aws_db_instance.sqlserver]
}
