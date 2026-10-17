# glue-streaming

Three Spark Structured Streaming jobs (medallion pattern) plus the Glue Data Catalog.

## Jobs

| Job | Script | Input → Output |
|---|---|---|
| `<prefix>-bronze` | `glue-jobs/bronze_ingest.py` | MSK CDC topics → Delta `bronze/dbo/<table>/` (append-only) |
| `<prefix>-silver` | `glue-jobs/silver_curate.py` | bronze → Delta `silver/dbo/<table>/` (dedupe + schema enforcement) |
| `<prefix>-gold` | `glue-jobs/gold_aggregate.py` | silver → Delta `gold/<mart>/` (hourly revenue, customer lifetime value) |

## Production settings (every job)

- Job bookmarks enabled (exactly-once-ish restart semantics with checkpoints)
- Autoscaling + continuous CloudWatch logging + job metrics
- VPC `NETWORK` connection (private MSK/RDS access)
- Per-job checkpoint location under `checkpoints/<layer>/`
- Delta Lake via `--conf spark.jars.packages` (Maven Central, reached through the NAT gateway); Delta SQL extensions are configured in the scripts themselves

## Staged-jar alternative

To avoid Maven at runtime (stricter prod environments), download `delta-spark_2.12-<version>.jar` into the scripts bucket and set `--extra-jars` on the jobs. The argument is already present (empty) as a placeholder.

## Catalog

One database (`<project>_<env>_lake`) with Delta tables registered for every bronze/silver table and both gold marts — queryable from Athena and Spark SQL immediately after the first micro-batch lands. Table schemas mirror the `table_schemas` local and the `glue-jobs/*.py` scripts; keep the three in sync when the demo schema changes.
