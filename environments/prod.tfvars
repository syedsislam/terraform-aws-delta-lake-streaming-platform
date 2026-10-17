# =============================================================================
# prod environment values
# =============================================================================

environment = "prod"
owner       = "data-platform-team@example.com"

# Production sizing: headroom for CDC backlogs and replays
msk_broker_instance_type = "kafka.m5.large"
msk_broker_count         = 3
msk_ebs_volume_size      = 200

rds_instance_class    = "db.m5.large"
rds_allocated_storage = 200
rds_multi_az          = true

dms_instance_class = "dms.c5.large"

glue_worker_type = "G.2X"
glue_workers     = 8

log_retention_days = 90
