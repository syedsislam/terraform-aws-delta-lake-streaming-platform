# =============================================================================
# Root module wiring
#
# Data flows left to right: SQL Server -> DMS -> MSK -> Glue streaming ->
# Delta Lake on S3. Each stage is an isolated child module with a clear
# contract (inputs in, outputs out). Cross-module data passes only through
# module outputs — never through data sources reaching into other modules.
# =============================================================================

module "networking" {
  source = "./modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "s3_data_lake" {
  source = "./modules/s3-data-lake"

  name_prefix           = local.name_prefix
  bucket_name_override  = var.data_lake_bucket_name
  bronze_retention_days = var.bronze_retention_days
  tags                  = local.common_tags
}

# The MSK log group name is deterministic ("/aws/msk/<prefix>") and created by
# the monitoring module. Passing it as a plain string avoids a dependency
# cycle between the msk and monitoring modules.
module "msk" {
  source = "./modules/msk"

  name_prefix          = local.name_prefix
  private_subnet_ids   = module.networking.private_subnet_ids
  security_group_ids   = [module.networking.msk_security_group_id]
  broker_instance_type = var.msk_broker_instance_type
  broker_count         = var.msk_broker_count
  ebs_volume_size      = var.msk_ebs_volume_size
  kafka_version        = var.kafka_version
  log_group_name       = "/aws/msk/${local.name_prefix}"
  tags                 = local.common_tags

  depends_on = [module.networking]
}

module "rds_mssql" {
  source = "./modules/rds-mssql"

  name_prefix          = local.name_prefix
  private_subnet_ids   = module.networking.private_subnet_ids
  security_group_ids   = [module.networking.rds_security_group_id]
  instance_class       = var.rds_instance_class
  allocated_storage    = var.rds_allocated_storage
  engine_version       = var.rds_engine_version
  multi_az             = var.rds_multi_az
  database_name        = var.source_database_name
  tags                 = local.common_tags
}

module "dms" {
  source = "./modules/dms"

  name_prefix                = local.name_prefix
  private_subnet_ids         = module.networking.private_subnet_ids
  security_group_ids         = [module.networking.dms_security_group_id]
  replication_instance_class = var.dms_instance_class
  engine_version             = var.dms_engine_version
  source_secret_arn          = module.rds_mssql.db_credentials_secret_arn
  source_endpoint_address    = module.rds_mssql.db_endpoint
  source_endpoint_port       = module.rds_mssql.db_port
  source_database_name       = var.source_database_name
  kafka_bootstrap_brokers    = module.msk.bootstrap_brokers_sasl_scram
  kafka_sasl_username        = module.msk.dms_scram_username
  kafka_sasl_password        = module.msk.dms_scram_password
  cdc_tables                 = var.cdc_tables
  cdc_topic_prefix           = local.cdc_topic_prefix
  vpc_role_arn               = module.iam.dms_vpc_role_arn
  tags                       = local.common_tags

  depends_on = [module.msk, module.rds_mssql, module.iam]
}

module "glue_streaming" {
  source = "./modules/glue-streaming"

  name_prefix         = local.name_prefix
  glue_role_arn       = module.iam.glue_job_role_arn
  glue_connection     = module.networking.glue_connection_name
  data_lake_bucket    = module.s3_data_lake.data_lake_bucket
  scripts_bucket      = module.s3_data_lake.scripts_bucket
  scripts_prefix      = module.s3_data_lake.scripts_prefix
  kafka_bootstrap     = module.msk.bootstrap_brokers_iam
  cdc_topic_prefix    = local.cdc_topic_prefix
  cdc_tables          = var.cdc_tables
  worker_type         = var.glue_worker_type
  number_of_workers   = var.glue_workers
  glue_version        = var.glue_version
  delta_spark_version = var.delta_spark_version
  tags                = local.common_tags

  depends_on = [module.msk, module.s3_data_lake, module.iam, module.networking]
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix              = local.name_prefix
  msk_cluster_name         = module.msk.cluster_name
  dms_replication_task_arn = module.dms.replication_task_arn
  glue_job_names           = module.glue_streaming.job_names
  rds_instance_id          = module.rds_mssql.db_instance_id
  log_retention_days       = var.log_retention_days
  alarm_sns_topic_name     = "${local.name_prefix}-alarms"
  tags                     = local.common_tags
}
