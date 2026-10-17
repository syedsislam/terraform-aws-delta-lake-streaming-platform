# =============================================================================
# monitoring module
#
# Observability for the streaming platform:
#   - CloudWatch log group for MSK broker logs
#   - SNS topic for alarm notifications
#   - Alarms: MSK (CPU, under-replicated partitions), DMS (CDC latency),
#     Glue (job failures), RDS (CPU, free storage)
#   - One dashboard with the key pipeline health widgets
# =============================================================================

# --- Log group for MSK broker logs (referenced by the msk module) ------------------

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "${var.name_prefix}-msk-logs" })
}

# --- Alarm notifications ------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name         = var.alarm_sns_topic_name
  display_name = "${var.name_prefix} pipeline alarms"

  tags = merge(var.tags, { Name = var.alarm_sns_topic_name })
}

# --- MSK alarms ----------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "msk_cpu" {
  alarm_name          = "${var.name_prefix}-msk-cpu-high"
  alarm_description   = "MSK broker CPU above 80% for 15 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CpuUser"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "msk_under_replicated" {
  alarm_name          = "${var.name_prefix}-msk-under-replicated-partitions"
  alarm_description   = "Under-replicated partitions detected on MSK"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

# --- DMS alarm: CDC latency ------------------------------------------------------------
# CDCLatencySource is the gap between source commit time and DMS capture; a
# growing value means the pipeline is falling behind the source database.

resource "aws_cloudwatch_metric_alarm" "dms_cdc_latency" {
  alarm_name          = "${var.name_prefix}-dms-cdc-latency-high"
  alarm_description   = "DMS CDC source latency above 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CDCLatencySource"
  namespace           = "AWS/DMS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    "ReplicationTaskIdentifier" = split(":", var.dms_replication_task_arn)[6]
  }

  tags = var.tags
}

# --- Glue alarms: failed runs ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "glue_job_failed" {
  for_each = toset(var.glue_job_names)

  alarm_name          = "${var.name_prefix}-glue-${each.value}-failed"
  alarm_description   = "Glue streaming job ${each.value} reported a failed run"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = each.value
  }

  tags = var.tags
}

# --- RDS alarms ----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS SQL Server CPU above 80% for 15 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.name_prefix}-rds-low-free-storage"
  alarm_description   = "RDS free storage below 20 GiB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 21474836480 # 20 GiB in bytes
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.tags
}

# --- Dashboard -------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.name_prefix}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "MSK: CPU and under-replicated partitions"
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/Kafka", "CpuUser", "Cluster Name", var.msk_cluster_name],
            ["AWS/Kafka", "UnderReplicatedPartitions", "Cluster Name", var.msk_cluster_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "DMS: CDC source latency"
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/DMS", "CDCLatencySource", "ReplicationTaskIdentifier", split(":", var.dms_replication_task_arn)[6]],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title   = "RDS: CPU and free storage"
          region  = data.aws_region.current.name
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id],
          ]
        }
      },
    ]
  })
}

data "aws_region" "current" {}
