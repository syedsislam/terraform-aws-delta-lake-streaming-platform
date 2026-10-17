# =============================================================================
# s3-data-lake module
#
# Two buckets:
#   - data lake: bronze/silver/gold Delta tables + streaming checkpoints.
#     Versioned, KMS-encrypted, lifecycle-managed, access-logged.
#   - scripts: Glue job Python files, versioned and encrypted.
#
# Layout inside the data lake bucket:
#   bronze/<schema>/<table>/        raw CDC events (Delta)
#   silver/<schema>/<table>/        deduped + cleansed (Delta)
#   gold/<mart>/                    business aggregates (Delta)
#   checkpoints/<job>/             Structured Streaming checkpoints
#   _tmp/                           Glue temporary directory
# =============================================================================

resource "random_pet" "bucket_suffix" {
  length    = 2
  separator = "-"
}

locals {
  data_lake_bucket = var.bucket_name_override != "" ? var.bucket_name_override : "${var.name_prefix}-data-lake-${random_pet.bucket_suffix.id}"
}

resource "aws_kms_key" "lake" {
  description             = "SSE-KMS key for ${var.name_prefix} data lake"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-lake-kms" })
}

resource "aws_kms_alias" "lake" {
  name          = "alias/${var.name_prefix}-data-lake"
  target_key_id = aws_kms_key.lake.key_id
}

# --- Data lake bucket ------------------------------------------------------------

resource "aws_s3_bucket" "data_lake" {
  bucket = local.data_lake_bucket

  tags = merge(var.tags, { Name = local.data_lake_bucket })
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.lake.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  # Bronze is the raw landing zone: keep it queryable, then tier it down.
  rule {
    id     = "bronze-tiering"
    status = "Enabled"
    filter {
      prefix = "bronze/"
    }
    transition {
      days          = var.bronze_retention_days
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = var.bronze_retention_days * 4
      storage_class = "GLACIER"
    }
  }

  # Checkpoints and temp files are operational, not analytical: expire them.
  rule {
    id     = "checkpoints-expiry"
    status = "Enabled"
    filter {
      prefix = "checkpoints/"
    }
    expiration {
      days = 90
    }
  }

  rule {
    id     = "tmp-expiry"
    status = "Enabled"
    filter {
      prefix = "_tmp/"
    }
    expiration {
      days = 7
    }
  }

  # Clean up incomplete multipart uploads left by failed streaming writes.
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Placeholder objects so the zone prefixes exist from day one (also serves as a
# smoke test that the deployer can write to the bucket).
resource "aws_s3_object" "zone_placeholders" {
  for_each = toset(var.lake_prefixes)

  bucket  = aws_s3_bucket.data_lake.id
  key     = "${each.value}/.keep"
  content = "Zone placeholder for the ${each.value} layer.\n"
}

# --- Access logging ---------------------------------------------------------------

resource "aws_s3_bucket" "access_logs" {
  bucket = "${local.data_lake_bucket}-logs"

  tags = merge(var.tags, { Name = "${local.data_lake_bucket}-logs" })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "data_lake" {
  bucket        = aws_s3_bucket.data_lake.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "data-lake-access/"
}

# --- Scripts bucket (Glue job Python files) ---------------------------------------

resource "aws_s3_bucket" "scripts" {
  bucket = "${var.name_prefix}-glue-scripts-${random_pet.bucket_suffix.id}"

  tags = merge(var.tags, { Name = "${var.name_prefix}-glue-scripts" })
}

resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.lake.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket                  = aws_s3_bucket.scripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the Glue job scripts from the repo so the jobs always run the
# committed code. Content hash forces a re-upload whenever a script changes.
resource "aws_s3_object" "glue_scripts" {
  for_each = fileset("${path.module}/../../glue-jobs", "*.py")

  bucket = aws_s3_bucket.scripts.id
  key    = "glue-jobs/${each.value}"
  source = "${path.module}/../../glue-jobs/${each.value}"
  etag   = filemd5("${path.module}/../../glue-jobs/${each.value}")

  tags = var.tags
}
