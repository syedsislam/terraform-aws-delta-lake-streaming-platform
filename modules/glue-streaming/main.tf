# =============================================================================
# glue-streaming module
#
# Three Spark Structured Streaming jobs implementing the medallion pattern:
#   bronze_ingest.py  — Kafka (MSK) -> Delta, raw CDC events, append-only
#   silver_curate.py  — bronze -> Delta, dedupe on CDC keys, schema enforcement
#   gold_aggregate.py — silver -> Delta, business marts (hourly revenue, CLV)
#
# Production settings on every job: bookmarks, autoscaling, continuous
# CloudWatch logging, job metrics, VPC connection, Delta Lake extensions and
# per-job checkpoint locations on S3.
#
# The Glue Data Catalog database and Delta table definitions are registered
# here so Athena/Spark SQL can query bronze/silver/gold immediately.
# =============================================================================

locals {
  jobs = {
    bronze = {
      script      = "bronze_ingest.py"
      description = "Raw CDC events from MSK into Delta bronze tables"
    }
    silver = {
      script      = "silver_curate.py"
      description = "Deduped, cleansed CDC data into Delta silver tables"
    }
    gold = {
      script      = "gold_aggregate.py"
      description = "Business aggregate marts into Delta gold tables"
    }
  }

  # Maven coordinates pulled at job start via --conf spark.jars.packages (the
  # VPC has a NAT gateway for Maven Central access); see README for the
  # staged-jar alternative. Includes the MSK IAM auth library so the Kafka
  # source can use SASL_SSL with the AWS_MSK_IAM mechanism.
  delta_packages = join(",", [
    "io.delta:delta-spark_2.12:${var.delta_spark_version}",
    "software.amazon.msk:aws-msk-iam-auth:1.1.9",
  ])

  # NOTE: default_arguments is a map, so only one "--conf" key is possible.
  # spark.jars.packages pulls the Delta connector from Maven Central at job
  # start (the VPC has a NAT gateway). The Delta SQL extensions and catalog
  # are configured inside the job scripts via SparkSession.builder.config(),
  # which keeps all Spark tuning next to the code it affects.
  common_job_args = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-auto-scaling"              = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--enable-glue-datacatalog"          = "true"
    "--TempDir"                          = "s3://${var.data_lake_bucket}/_tmp/"
    "--kafka-bootstrap-servers"          = var.kafka_bootstrap
    "--cdc-topic-prefix"                 = var.cdc_topic_prefix
    "--cdc-tables"                       = join(",", var.cdc_tables)
    "--data-lake-bucket"                 = var.data_lake_bucket
    "--catalog-database"                 = aws_glue_catalog_database.lake.name
    "--conf"                             = "spark.jars.packages=${local.delta_packages}"
    "--datalake-formats"                 = "delta"
  }
}

resource "aws_glue_catalog_database" "lake" {
  name        = replace("${var.name_prefix}-lake", "-", "_")
  description = "Delta Lake bronze/silver/gold tables for ${var.name_prefix}"

  tags = var.tags
}

# --- Streaming jobs ---------------------------------------------------------------

resource "aws_glue_job" "streaming" {
  for_each = local.jobs

  name              = "${var.name_prefix}-${each.key}"
  description       = each.value.description
  role_arn          = var.glue_role_arn
  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  max_retries       = 2
  timeout           = 2880 # 48h: streaming jobs run continuously; timeout is a backstop
  execution_class   = "STANDARD"

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket}/${var.scripts_prefix}/${each.value.script}"
    python_version  = "3"
  }

  connections = [var.glue_connection]

  default_arguments = merge(
    local.common_job_args,
    {
      "--checkpoint-location" = "s3://${var.data_lake_bucket}/checkpoints/${each.key}/"
      "--extra-jars"          = "" # reserved: point at a staged Delta jar to avoid Maven at runtime
      "--job-name"            = "${var.name_prefix}-${each.key}"
    }
  )

  # Delta Lake needs the connector on the classpath; spark.jars.packages pulls
  # it from Maven Central at job start (documented alternative: stage the jar
  # in the scripts bucket and set --extra-jars above).
  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

# --- Catalog table definitions -----------------------------------------------------
# Business schemas of the demo source (must match glue-jobs/*.py).

locals {
  # CDC envelope columns present on every bronze/silver row.
  cdc_envelope_columns = [
    { name = "_cdc_op", type = "string", comment = "insert | update | delete" },
    { name = "_cdc_ts", type = "timestamp", comment = "Source commit timestamp" },
  ]

  table_schemas = {
    "orders" = {
      schema = "dbo"
      business_columns = [
        { name = "order_id", type = "bigint", comment = "Primary key" },
        { name = "customer_id", type = "bigint", comment = "FK to customers" },
        { name = "product_id", type = "bigint", comment = "FK to products" },
        { name = "quantity", type = "int", comment = "" },
        { name = "unit_price", type = "decimal(10,2)", comment = "" },
        { name = "order_ts", type = "timestamp", comment = "Business event time" },
        { name = "status", type = "string", comment = "" },
      ]
      keys = ["order_id"]
    }
    "customers" = {
      schema = "dbo"
      business_columns = [
        { name = "customer_id", type = "bigint", comment = "Primary key" },
        { name = "first_name", type = "string", comment = "" },
        { name = "last_name", type = "string", comment = "" },
        { name = "email", type = "string", comment = "" },
        { name = "country", type = "string", comment = "" },
        { name = "created_ts", type = "timestamp", comment = "" },
      ]
      keys = ["customer_id"]
    }
    "products" = {
      schema = "dbo"
      business_columns = [
        { name = "product_id", type = "bigint", comment = "Primary key" },
        { name = "product_name", type = "string", comment = "" },
        { name = "category", type = "string", comment = "" },
        { name = "list_price", type = "decimal(10,2)", comment = "" },
      ]
      keys = ["product_id"]
    }
  }

  # "dbo.orders" -> "orders"
  cdc_table_names = [for t in var.cdc_tables : split(".", t)[1]]

  gold_marts = {
    hourly_revenue = {
      description = "Revenue per product category per hour"
      columns = [
        { name = "window_start", type = "timestamp", comment = "" },
        { name = "window_end", type = "timestamp", comment = "" },
        { name = "category", type = "string", comment = "" },
        { name = "order_count", type = "bigint", comment = "" },
        { name = "total_revenue", type = "decimal(18,2)", comment = "" },
      ]
    }
    customer_lifetime_value = {
      description = "Per-customer lifetime spend"
      columns = [
        { name = "customer_id", type = "bigint", comment = "" },
        { name = "email", type = "string", comment = "" },
        { name = "total_orders", type = "bigint", comment = "" },
        { name = "total_spent", type = "decimal(18,2)", comment = "" },
        { name = "last_order_ts", type = "timestamp", comment = "" },
      ]
    }
  }
}

# Bronze + silver tables: one per CDC table per layer.
resource "aws_glue_catalog_table" "layer_tables" {
  for_each = {
    for pair in setproduct(["bronze", "silver"], local.cdc_table_names) :
    "${pair[0]}_${pair[1]}" => { layer = pair[0], table = pair[1] }
  }

  name          = "${each.value.layer}_${each.value.table}"
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "table_type"     = "DELTA"
    "classification" = "delta"
  }

  storage_descriptor {
    location      = "s3://${var.data_lake_bucket}/${each.value.layer}/dbo/${each.value.table}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = concat(
        local.table_schemas[each.value.table].business_columns,
        local.cdc_envelope_columns,
        [{ name = "_ingest_ts", type = "timestamp", comment = "Bronze/silver write time" }],
      )
      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }

  tags = var.tags
}

# Gold marts.
resource "aws_glue_catalog_table" "gold_marts" {
  for_each = local.gold_marts

  name          = "gold_${each.key}"
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "table_type"     = "DELTA"
    "classification" = "delta"
  }

  storage_descriptor {
    location      = "s3://${var.data_lake_bucket}/gold/${each.key}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = each.value.columns
      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }

  tags = var.tags
}
