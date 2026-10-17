# =============================================================================
# iam module
#
# Least-privilege roles for the platform:
#   - Glue streaming job role (service role + narrow data-plane policy)
#   - The two AWS-managed DMS service roles (exact names AWS requires)
#
# No role gets "*". Every policy scopes actions to this platform's resources.
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# --- Glue streaming job role --------------------------------------------------------

resource "aws_iam_role" "glue_job" {
  name        = "${var.name_prefix}-glue-job-role"
  description = "Assumed by the bronze/silver/gold Glue streaming jobs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-glue-job-role" })
}

# AWS-managed Glue service permissions (covers CloudWatch logs, metrics, EC2
# ENI management for the VPC connection).
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Narrow data-plane policy: S3 data lake + scripts, KMS, MSK IAM auth, catalog.
resource "aws_iam_policy" "glue_data_plane" {
  name        = "${var.name_prefix}-glue-data-plane"
  description = "Least-privilege data-plane access for ${var.name_prefix} Glue streaming jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3DataLake"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          "arn:aws:s3:::${var.name_prefix}-data-lake-*",
          "arn:aws:s3:::${var.name_prefix}-data-lake-*/*",
          "arn:aws:s3:::${var.name_prefix}-glue-scripts-*",
          "arn:aws:s3:::${var.name_prefix}-glue-scripts-*/*",
        ]
      },
      {
        Sid      = "KMS"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "arn:aws:kms:${local.region}:${local.account_id}:key/*"
        Condition = {
          StringLike = {
            "kms:ViaService" = ["s3.${local.region}.amazonaws.com", "kafka.${local.region}.amazonaws.com"]
          }
        }
      },
      {
        Sid    = "MSKIAMAuth"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup",
        ]
        Resource = [
          "arn:aws:kafka:${local.region}:${local.account_id}:cluster/${var.name_prefix}-msk/*",
          "arn:aws:kafka:${local.region}:${local.account_id}:topic/${var.name_prefix}-msk/*/*",
          "arn:aws:kafka:${local.region}:${local.account_id}:group/${var.name_prefix}-msk/*/*",
        ]
      },
      {
        Sid      = "GlueCatalog"
        Effect   = "Allow"
        Action   = ["glue:GetTable", "glue:GetTables", "glue:UpdateTable", "glue:CreateTable", "glue:GetDatabase", "glue:GetPartitions"]
        Resource = [
          "arn:aws:glue:${local.region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.region}:${local.account_id}:database/${replace(var.name_prefix, "-", "_")}_lake",
          "arn:aws:glue:${local.region}:${local.account_id}:table/${replace(var.name_prefix, "-", "_")}_lake/*",
        ]
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_data_plane" {
  role       = aws_iam_role.glue_job.name
  policy_arn = aws_iam_policy.glue_data_plane.arn
}

# --- AWS-managed DMS service roles (exact names required by DMS) --------------------
# DMS refuses to create replication instances unless these two roles exist.

resource "aws_iam_role" "dms_vpc" {
  name        = "dms-vpc-role"
  description = "Allows DMS to manage VPC resources (managed by ${var.name_prefix} Terraform)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "dms-vpc-role" })
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms_vpc.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch_logs" {
  name        = "dms-cloudwatch-logs-role"
  description = "Allows DMS to publish logs to CloudWatch (managed by ${var.name_prefix} Terraform)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "dms-cloudwatch-logs-role" })
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs" {
  role       = aws_iam_role.dms_cloudwatch_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# DMS reads the SQL Server credentials from Secrets Manager at endpoint
# test/start time.
resource "aws_iam_policy" "dms_secrets" {
  name        = "${var.name_prefix}-dms-secrets"
  description = "Allow DMS to read source DB credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.name_prefix}-sqlserver-credentials*"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_secrets" {
  role       = aws_iam_role.dms_vpc.name
  policy_arn = aws_iam_policy.dms_secrets.policy_arn
}
