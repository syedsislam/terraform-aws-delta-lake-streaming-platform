"""
Bronze ingestion job: MSK CDC topics -> Delta Lake (append-only).

Reads the JSON CDC events produced by DMS from one Kafka topic per table
(sqlserver.cdc.<schema>.<table>), parses the DMS envelope, and appends every
event to the matching Delta bronze table with an ingestion timestamp.

Bronze is intentionally raw: no dedupe, no cleansing. It is the replayable
system of record — silver and gold can always be rebuilt from here.

Expected DMS JSON event shape per message:
    {
      "data":     { ...row columns... },
      "metadata": {
        "operation": "insert" | "update" | "delete",
        "timestamp": "2026-10-17T12:34:56.789Z"
      }
    }
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, current_timestamp, to_timestamp
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
)

# --- Job parameters (injected by Terraform default_arguments) --------------------
args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "kafka-bootstrap-servers",
        "cdc-topic-prefix",
        "cdc-tables",
        "data-lake-bucket",
        "checkpoint-location",
    ],
)

BOOTSTRAP_SERVERS = args["kafka-bootstrap-servers"]
TOPIC_PREFIX = args["cdc-topic-prefix"]
TABLES = [t.strip() for t in args["cdc-tables"].split(",") if t.strip()]
LAKE_BUCKET = args["data-lake-bucket"]
CHECKPOINT = args["checkpoint-location"].rstrip("/")

DELTA_VERSION = "2.4.0"  # must match var.delta_spark_version

# --- Spark session -----------------------------------------------------------------
spark = (
    SparkSession.builder.appName(args["JOB_NAME"])
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config(
        "spark.sql.catalog.spark_catalog",
        "org.apache.spark.sql.delta.catalog.DeltaCatalog",
    )
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

# --- Schemas -------------------------------------------------------------------------
# The metadata envelope is fixed; the row payload is kept as a flexible struct
# at bronze (schema enforcement happens in silver).
metadata_schema = StructType(
    [
        StructField("operation", StringType(), True),
        StructField("timestamp", StringType(), True),
    ]
)

event_schema = StructType(
    [
        StructField("data", StringType(), True),  # raw row JSON, parsed downstream
        StructField("metadata", metadata_schema, True),
    ]
)


def bronze_path(schema: str, table: str) -> str:
    return f"s3://{LAKE_BUCKET}/bronze/{schema}/{table}/"


def topic_for(schema: str, table: str) -> str:
    return f"{TOPIC_PREFIX}.{schema}.{table}"


# --- One streaming query per table ------------------------------------------------------
# Separate queries (and checkpoint dirs) per table isolate failures: a poison
# pill in one table's topic cannot stall ingestion of the others.

queries = []
for qualified in TABLES:
    schema, table = qualified.split(".")
    topic = topic_for(schema, table)

    raw = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", BOOTSTRAP_SERVERS)
        .option("kafka.security.protocol", "SASL_SSL")
        .option("kafka.sasl.mechanism", "AWS_MSK_IAM")
        .option(
            "kafka.sasl.jaas.config",
            "software.amazon.msk.auth.iam.IAMLoginModule required;",
        )
        .option("kafka.sasl.client.callback.handler.class",
                "software.amazon.msk.auth.iam.IAMClientCallbackHandler")
        .option("subscribe", topic)
        .option("startingOffsets", "earliest")
        .option("failOnDataLoss", "false")
        .load()
    )

    parsed = (
        raw.select(from_json(col("value").cast("string"), event_schema).alias("event"))
        .select(
            col("event.data").alias("row_json"),
            col("event.metadata.operation").alias("_cdc_op"),
            to_timestamp(col("event.metadata.timestamp")).alias("_cdc_ts"),
        )
        .withColumn("_ingest_ts", current_timestamp())
    )

    query = (
        parsed.writeStream.format("delta")
        .outputMode("append")
        .option("checkpointLocation", f"{CHECKPOINT}/{schema}_{table}")
        .trigger(processingTime="60 seconds")
        .start(bronze_path(schema, table))
    )
    queries.append(query)
    print(f"Started bronze stream: topic={topic} -> {bronze_path(schema, table)}")

for q in queries:
    q.awaitTermination()
