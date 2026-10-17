# Architecture & Design Decisions

## Data flow

```
SQL Server (CDC) → DMS (full load + CDC) → MSK topics → Glue streaming
    → bronze (raw Delta) → silver (deduped Delta) → gold (marts, Delta)
```

Every stage is independently replayable: bronze is append-only raw history, so silver and gold can always be rebuilt. Checkpoints per job per table isolate failures.

## Why DMS instead of Debezium / self-managed Kafka Connect?

| Concern | DMS | Debezium on ECS/EKS |
|---|---|---|
| Operations | Fully managed, Multi-AZ replication instance | You own the connector cluster, offsets, restarts |
| SQL Server CDC | Native log-based capture via CDC tables | Same, but you tune it |
| Terraform story | First-class `aws_dms_*` resources | You'd Terraform the compute *around* Debezium, not Debezium itself |
| Fit for this project | Demonstrates managed-service composition, IAM, networking — the DevOps skill set | More moving parts, weaker "production-grade with less toil" narrative |

DMS is the pragmatic choice for a portfolio: it shows you can evaluate build-vs-buy and pick the managed path where it fits. The architecture doesn't depend on it — swapping in Debezium later only changes the ingest module.

## Why Delta Lake on S3 (not plain Parquet, not Hudi/Iceberg)?

- **ACID merges**: silver's CDC upsert/delete semantics need transactions; plain Parquet can't do that.
- **Time travel**: `VERSION AS OF` / `TIMESTAMP AS OF` make debugging and replays trivial.
- **Schema enforcement + evolution**: bronze stays flexible, silver enforces — Delta supports both modes.
- **Ecosystem**: first-class Spark support, Athena/Redshift Spectrum readable. Hudi and Iceberg are credible alternatives; Delta was chosen for the deepest Glue/Spark integration story.

## Why this auth mix on MSK?

- **Glue → MSK: IAM (SASL_SSL)**. Role-based, no secrets to rotate — the modern AWS-native pattern.
- **DMS → MSK: SCRAM (SASL_SSL)**. AWS DMS Kafka targets do *not* support MSK IAM access control (documented limitation), so a SCRAM credential in Secrets Manager is the correct, fully-automated alternative. Documenting a real platform limitation and its workaround is exactly the kind of thing interviewers probe for.

## Networking

All data-plane workloads live in private subnets. The S3 gateway endpoint and Glue interface endpoint keep lake and API traffic off the public internet; a single NAT gateway covers the residual egress (Maven Central for job jars, DMS updates). Security groups reference each other rather than CIDR blocks, so rules survive subnet changes.

## State management

Remote state in S3 with DynamoDB locking, using **partial backend configuration** (`backend.tf` declares the backend; `backend.<env>.hcl` supplies bucket/key/region/table at init). This keeps environment-specific state locations out of the codebase — one code path, N environments.

## Environments

`dev` is deliberately small (t3.small brokers, single-AZ RDS, 2× G.1X workers) for cheap iteration; `prod` adds headroom (m5.large, Multi-AZ, 8× G.2X). Same modules, different `.tfvars` — environment parity by construction.

## On-prem SQL Server variant

Replace the `rds-mssql` module's outputs with the on-prem host in the DMS source endpoint configuration; topics, jobs, tables, and IAM are unchanged. DMS supports on-prem SQL Server as a source identically (VPN/Direct Connect provides the network path).
