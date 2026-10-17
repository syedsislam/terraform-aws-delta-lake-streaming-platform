# dms

AWS DMS replication: SQL Server → MSK (full load + ongoing CDC).

## How it works

1. **Full load** — existing rows are bulk-copied into the Kafka topics.
2. **CDC** — DMS tails the SQL Server CDC capture tables and streams every insert/update/delete as a JSON event.

## Table mappings

Built from `cdc_tables` with `jsonencode` (no hand-written JSON blobs):

- **Selection rules** replicate exactly the listed `schema.table` pairs.
- **Rename transformations** set each Kafka topic to `sqlserver.cdc.<schema>.<table>`, so producers and consumers share one explicit naming contract.

## Authentication

- Source credentials come from Secrets Manager (the RDS module's secret) — never in Terraform config or state outputs.
- The MSK target uses SASL_SSL with SCRAM credentials provisioned by the `msk` module (stored in Secrets Manager, associated with the cluster). AWS DMS Kafka targets do not support MSK IAM access control, so SCRAM is required here; the Glue consumers use IAM.

## Prerequisites

CDC must be enabled on the source database first (`scripts/enable_cdc.sql`, see `docs/runbook.md`), and the RDS backup retention must be ≥ 1 day (enforced by a variable validation in `rds-mssql`).
