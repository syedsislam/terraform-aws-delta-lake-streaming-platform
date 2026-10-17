# iam

Least-privilege IAM for the platform.

## Roles

| Role | Used by | Permissions |
|---|---|---|
| `<prefix>-glue-job-role` | Bronze/silver/gold streaming jobs | `AWSGlueServiceRole` (managed) + a custom data-plane policy |
| `dms-vpc-role` | DMS replication instance | `AmazonDMSVPCManagementRole` (managed) + Secrets Manager read for the SQL Server credentials |
| `dms-cloudwatch-logs-role` | DMS replication instance | `AmazonDMSCloudWatchLogsRole` (managed) |

## Data-plane policy highlights

- S3 scoped to the platform's data-lake and scripts buckets (wildcard on the generated suffix).
- KMS scoped via `kms:ViaService` conditions (S3 + MSK only).
- MSK IAM auth scoped to the platform cluster, its topics and consumer groups.
- Glue catalog scoped to the platform database.

## Note on the DMS role names

`dms-vpc-role` and `dms-cloudwatch-logs-role` are the exact names AWS DMS requires. If your account already has them (e.g. from the console), import them instead of creating duplicates — see `docs/runbook.md`.
