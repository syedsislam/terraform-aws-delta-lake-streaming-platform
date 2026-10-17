"""
Gold aggregation job: silver Delta -> gold Delta marts.

Builds two business marts from the curated silver tables:

  1. gold/hourly_revenue/ — revenue per product category per hour
     (window on order_ts, sum of quantity * unit_price).
  2. gold/customer_lifetime_value/ — per-customer lifetime spend
     (count of orders, total spent, last order timestamp).

Both marts are rebuilt from silver with MERGE on each micro-batch, keyed by
their natural business keys, so replays are idempotent.
"""

import sys
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    sum as _sum,
    count as _count,
    max as _max,
    window,
    current_timestamp,
    round as _round,
)
from delta.tables import DeltaTable

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "data-lake-bucket",
        "checkpoint-location",
    ],
)

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

SILVER = f"s3://{LAKE_BUCKET}/silver/dbo"
GOLD = f"s3://{LAKE_BUCKET}/gold"


def merge_into(path: str, batch_df, keys: list) -> None:
    """Idempotent MERGE of an aggregate batch into a gold mart."""
    if batch_df.rdd.isEmpty():
        return

    enriched = batch_df.withColumn("_mart_ts", current_timestamp())

    if not DeltaTable.isDeltaTable(spark, path):
        enriched.write.format("delta").mode("overwrite").save(path)
        print(f"gold seed: created {path}")
        return

    mart = DeltaTable.forPath(spark, path)
    condition = " AND ".join(f"tgt.{k} = src.{k}" for k in keys)
    update_map = {
        c: f"src.{c}" for c in enriched.columns if c not in keys
    }

    (
        mart.alias("tgt")
        .merge(enriched.alias("src"), condition)
        .whenMatchedUpdate(set=update_map)
        .whenNotMatchedInsertAll()
        .execute()
    )


# --- Mart 1: hourly revenue by product category --------------------------------------
orders = spark.readStream.format("delta").load(f"{SILVER}/orders/")
products = spark.readStream.format("delta").load(f"{SILVER}/products/")

# Join the two silver streams on product_id. A 1-hour watermark bounds the
# state: late orders older than an hour are dropped from the aggregation
# (they remain queryable in silver).
revenue_events = (
    orders.withWatermark("order_ts", "1 hour")
    .join(products, on="product_id", how="inner")
    .filter(col("_cdc_op") != "delete")
)

hourly_revenue = (
    revenue_events.groupBy(
        window(col("order_ts"), "1 hour").alias("w"),
        col("category"),
    )
    .agg(
        _count("*").alias("order_count"),
        _round(_sum(col("quantity") * col("unit_price")), 2).alias("total_revenue"),
    )
    .select(
        col("w.start").alias("window_start"),
        col("w.end").alias("window_end"),
        col("category"),
        col("order_count"),
        col("total_revenue"),
    )
)

revenue_query = (
    hourly_revenue.writeStream.foreachBatch(
        lambda df, bid: merge_into(
            f"{GOLD}/hourly_revenue/", df, ["window_start", "category"]
        )
    )
    .outputMode("update")
    .option("checkpointLocation", f"{CHECKPOINT}/hourly_revenue")
    .trigger(processingTime="5 minutes")
    .start()
)
print("Started gold stream: hourly_revenue")

# --- Mart 2: customer lifetime value -------------------------------------------------
# NOTE: reading the same silver orders stream twice requires a second
# readStream (a streaming DataFrame cannot be reused across queries).

orders_for_clv = spark.readStream.format("delta").load(f"{SILVER}/orders/")
customers = spark.readStream.format("delta").load(f"{SILVER}/customers/")

clv_events = (
    orders_for_clv.withWatermark("order_ts", "1 hour")
    .join(customers, on="customer_id", how="inner")
    .filter(col("_cdc_op") != "delete")
)

customer_lifetime_value = (
    clv_events.groupBy(col("customer_id"), col("email"))
    .agg(
        _count("*").alias("total_orders"),
        _round(_sum(col("quantity") * col("unit_price")), 2).alias("total_spent"),
        _max(col("order_ts")).alias("last_order_ts"),
    )
)

clv_query = (
    customer_lifetime_value.writeStream.foreachBatch(
        lambda df, bid: merge_into(
            f"{GOLD}/customer_lifetime_value/", df, ["customer_id"]
        )
    )
    .outputMode("update")
    .option("checkpointLocation", f"{CHECKPOINT}/customer_lifetime_value")
    .trigger(processingTime="5 minutes")
    .start()
)
print("Started gold stream: customer_lifetime_value")

revenue_query.awaitTermination()
clv_query.awaitTermination()
