# =============================================================================
# msk module
#
# Amazon MSK (provisioned) cluster that buffers CDC events between DMS and the
# Glue streaming jobs. Hardened for production:
#   - TLS in transit + IAM client authentication (no plaintext, no SCRAM
#     secrets to rotate)
#   - Encryption at rest via AWS-managed KMS
#   - Enhanced PER_TOPIC monitoring (needed for lag-based alerting)
#   - Storage autoscaling so a CDC backlog cannot fill the brokers
# =============================================================================

resource "aws_msk_configuration" "main" {
  kafka_versions = [var.kafka_version]
  name           = "${var.name_prefix}-kafka-config"

  # DMS requires auto.create.topics.enable=true so it can create the CDC
  # topics on first produce (AWS DMS documentation, "Using Apache Kafka as a
  # target"). Topic NAMES are still fully controlled by the DMS table-mapping
  # rename rules in the dms module — auto-creation only materialises them.
  server_properties = <<-PROPERTIES
    auto.create.topics.enable=true
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=6
    log.retention.hours=168
  PROPERTIES
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${var.name_prefix}-msk"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count
  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.private_subnet_ids
    security_groups = var.security_group_ids

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size
      }
    }
  }

  # Two SASL mechanisms, two audiences:
  #   - IAM  -> Glue streaming jobs (role-based, nothing to rotate)
  #   - SCRAM -> DMS producer (DMS Kafka targets do not support MSK IAM
  #     access control per AWS documentation, so SCRAM is required here)
  client_authentication {
    sasl {
      iam   = true
      scram = true
    }
    tls {
      certificate_authority_arns = []
    }
    unauthenticated = false
  }

  encryption_info {
    encryption_in_transit_client_broker = "TLS"
    encryption_in_transit_in_cluster    = true
    encryption_at_rest_kms_key_arn      = aws_kms_key.msk.arn
  }

  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = var.log_group_name
      }
    }
  }

  storage_mode = "LOCAL"

  tags = merge(var.tags, { Name = "${var.name_prefix}-msk" })
}

# --- SCRAM credentials for the DMS producer ---------------------------------------
# DMS Kafka targets cannot use MSK IAM access control, so the DMS producer
# authenticates with SASL/SCRAM. Credentials live in Secrets Manager and are
# associated with the cluster; rotation = update the secret + the DMS endpoint.

resource "random_password" "dms_scram" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "aws_secretsmanager_secret" "dms_scram" {
  name                    = "${var.name_prefix}-msk-dms-scram"
  description             = "SCRAM credentials for the DMS producer on ${var.name_prefix} MSK"
  recovery_window_in_days = 30

  tags = merge(var.tags, { Name = "${var.name_prefix}-msk-dms-scram" })
}

resource "aws_secretsmanager_secret_version" "dms_scram" {
  secret_id = aws_secretsmanager_secret.dms_scram.id
  secret_string = jsonencode({
    username = var.dms_scram_username
    password = random_password.dms_scram.result
  })
}

# MSK needs permission to read the SCRAM secret at authentication time.
resource "aws_secretsmanager_secret_policy" "dms_scram" {
  secret_arn = aws_secretsmanager_secret.dms_scram.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "kafka.amazonaws.com" }
        Action    = "secretsmanager:GetSecretValue"
        Resource  = aws_secretsmanager_secret.dms_scram.arn
      }
    ]
  })
}

resource "aws_msk_scram_secret_association" "dms" {
  cluster_arn     = aws_msk_cluster.main.arn
  secret_arn_list = [aws_secretsmanager_secret.dms_scram.arn]

  depends_on = [aws_secretsmanager_secret_policy.dms_scram]
}

# Dedicated KMS key so broker encryption is independent of the S3 key and can
# be rotated or revoked without touching the data lake.
resource "aws_kms_key" "msk" {
  description             = "MSK at-rest encryption for ${var.name_prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-msk-kms" })
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${var.name_prefix}-msk"
  target_key_id = aws_kms_key.msk.key_id
}

# Storage autoscaling: a CDC backlog (e.g. a long DMS outage) grows broker
# storage instead of failing the cluster.
resource "aws_appautoscaling_target" "msk_storage" {
  max_capacity       = var.ebs_volume_size * 4
  min_capacity       = var.ebs_volume_size
  resource_id        = aws_msk_cluster.main.cluster_name
  scalable_dimension = "kafka:broker-storage:VolumeSize"
  service_namespace  = "kafka"
}

resource "aws_appautoscaling_policy" "msk_storage" {
  name               = "${var.name_prefix}-msk-storage-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.msk_storage.resource_id
  scalable_dimension = aws_appautoscaling_target.msk_storage.scalable_dimension
  service_namespace  = aws_appautoscaling_target.msk_storage.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60.0

    customized_metric_specification {
      metrics {
        label = "KafkaDataLogsDiskUsed"
        metric_stat {
          metric {
            metric_name = "KafkaDataLogsDiskUsed"
            namespace   = "AWS/Kafka"
            dimensions {
              name  = "Cluster Name"
              value = aws_msk_cluster.main.cluster_name
            }
          }
          stat = "Average"
        }
        return_data = true
      }
    }
  }
}
