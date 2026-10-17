"""
Silver curation job: bronze Delta -> silver Delta.

For each table this job:
  1. Reads the bronze Delta table as a stream.
  2. Parses the raw row JSON into the typed business schema (schema
     enforcement — malformed rows are quarantined, not dropped silently).
  3. Dedupes on the business primary key, keeping the latest CDC event
     (row_number over the key ordered by _cdc_ts desc).
  4. Applies deletes (CDC operation = "delete") and writes the result with
     Delta MERGE semantics via foreachBatch.

Deletes are applied as true deletes so silver always reflects the current
state of the source table — the pattern downstream marts expect.
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    from_json,
    current_timestamp,
    row_number,
    to_timestamp,
)
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
    LongType,
    DecimalType,
    TimestampType,
)
from pyspark.sql.window import Window
from delta.tables import DeltaTable

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "cdc-tables",
        "data-lake-bucket",
        "checkpoint-location",
    ],
)

TABLES = [t.strip() for t in args["cdc-tables"].split(",") if t.strip()]
LAKE_BUCKET = args["data-lake-bucket"]
CHECKPOINT = args["checkpoint-location"].rstrip("/")

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

# --- Business schemas (must match the Terraform table_schemas local) -------------------
TABLE_SCHEMAS = {
    "orders": (
        StructType(
            [
                StructField("order_id", LongType(), False),
                StructField("customer_id", LongType(), True),
                StructField("product_id", LongType(), True),
                StructField("quantity", IntegerType(), True),
                StructField("unit_price", DecimalType(10, 2), True),
                StructField("order_ts", TimestampType(), True),
                StructField("status", StringType(), True),
            ]
        ),
        ["order_id"],
    ),
    "customers": (
        StructType(
            [
                StructField("customer_id", LongType(), False),
                StructField("first_name", StringType(), True),
                StructField("last_name", StringType(), True),
                StructField("email", StringType(), True),
                StructField("country", StringType(), True),
                StructField("created_ts", TimestampType(), True),
            ]
        ),
        ["customer_id"],
    ),
    "products": (
        StructType(
            [
                StructField("product_id", LongType(), False),
                StructField("product_name", StringType(), True),
                StructField("category", StringType(), True),
                StructField("list_price", DecimalType(10, 2), True),
            ]
        ),
        ["product_id"],
    ),
}


def bronze_path(schema: str, table: str) -> str:
    return f"s3://{LAKE_BUCKET}/bronze/{schema}/{table}/"


def silver_path(schema: str, table: str) -> str:
    return f"s3://{LAKE_BUCKET}/silver/{schema}/{table}/"


def quarantine_path(schema: str, table: str) -> str:
    return f"s3://{LAKE_BUCKET}/silver/{schema}/{table}/_quarantine/"


def upsert_to_silver(micro_batch_df, batch_id: int, schema: str, table: str,
                     row_schema: StructType, keys: list) -> None:
    """Apply one micro-batch to the silver table with MERGE semantics."""
    if micro_batch_df.rdd.isEmpty():
        return

    # Parse the raw row JSON; rows that fail parsing go to quarantine.
    parsed = micro_batch_df.withColumn(
        "row", from_json(col("row_json"), row_schema)
    )
    valid = parsed.filter(col("row").isNotNull()).select(
        col("row.*"), col("_cdc_op"), col("_cdc_ts")
    )
    invalid = parsed.filter(col("row").isNull())
    if not invalid.rdd.isEmpty():
        (
            invalid.drop("row")
            .withColumn("_quarantined_ts", current_timestamp())
            .write.format("delta")
            .mode("append")
            .save(quarantine_path(schema, table))
        )

    # Dedupe: keep the latest CDC event per business key.
    window = Window.partitionBy(*keys).orderBy(col("_cdc_ts").desc_nulls_last())
    deduped = (
        valid.withColumn("_rn", row_number().over(window))
        .filter(col("_rn") == 1)
        .drop("_rn")
        .withColumn("_ingest_ts", current_timestamp())
    )

    target_path = silver_path(schema, table)

    # First micro-batch seeds the table; every later batch merges into it.
    # (foreachBatch runs single-threaded per query, so there is no race here.)
    if not DeltaTable.isDeltaTable(spark, target_path):
        (
            deduped.write.format("delta")
            .mode("overwrite")
            .save(target_path)
        )
        print(f"silver seed batch {batch_id}: created {schema}.{table}")
        return

    silver = DeltaTable.forPath(spark, target_path)
    merge_condition = " AND ".join(f"tgt.{k} = src.{k}" for k in keys)

    # Columns refreshed on update: every non-key business column plus the
    # CDC envelope. Delta's Python API takes a column->expression dict.
    update_map = {
        c.name: f"src.{c.name}" for c in row_schema.fields if c.name not in keys
    }
    update_map.update(
        {
            "_cdc_op": "src._cdc_op",
            "_cdc_ts": "src._cdc_ts",
            "_ingest_ts": "src._ingest_ts",
        }
    )

    (
        silver.alias("tgt")
        .merge(deduped.alias("src"), merge_condition)
        # CDC deletes become real deletes in silver.
        .whenMatchedDelete(condition="src._cdc_op = 'delete'")
        .whenMatchedUpdate(condition="src._cdc_op != 'delete'", set=update_map)
        .whenNotMatchedInsertAll()
        .execute()
    )
    print(f"silver upsert batch {batch_id}: {schema}.{table} merged")


queries = []
for qualified in TABLES:
    schema, table = qualified.split(".")
    row_schema, keys = TABLE_SCHEMAS[table]

    bronze_stream = spark.readStream.format("delta").load(bronze_path(schema, table))

    # Capture loop variables for the foreachBatch closure.
    def make_upsert(s=schema, t=table, rs=row_schema, k=keys):
        return lambda df, bid: upsert_to_silver(df, bid, s, t, rs, k)

    query = (
        bronze_stream.writeStream.foreachBatch(make_upsert())
        .outputMode("update")
        .option("checkpointLocation", f"{CHECKPOINT}/{schema}_{table}")
        .trigger(processingTime="120 seconds")
        .start()
    )
    queries.append(query)
    print(f"Started silver stream: {schema}.{table}")

for q in queries:
    q.awaitTermination()
