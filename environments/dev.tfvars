# =============================================================================
# dev environment values
# =============================================================================

environment = "dev"
owner       = "data-platform-team@example.com"

# Small, cheap footprint for iteration
msk_broker_instance_type = "kafka.t3.small"
msk_broker_count         = 3
msk_ebs_volume_size      = 50

rds_instance_class    = "db.t3.medium"
rds_allocated_storage = 50
rds_multi_az          = false

dms_instance_class = "dms.t3.medium"

glue_worker_type = "G.1X"
glue_workers     = 2

log_retention_days = 14
