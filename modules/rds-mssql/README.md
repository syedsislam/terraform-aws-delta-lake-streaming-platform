# rds-mssql

Amazon RDS for SQL Server (Standard Edition) as the CDC source.

## Security posture

- Private subnets only, TDS (1433) reachable solely from the DMS security group.
- Storage encrypted; master password is a 32-char random secret in Secrets Manager — never in variables or state outputs.
- Deletion protection on by default; final snapshot on destroy.

## CDC enablement

RDS SQL Server enables CDC through `msdb` stored procedures (`rds_cdc_enable_db`), which Terraform cannot invoke. After `terraform apply`, run `scripts/enable_cdc.sql` once against the instance (see `docs/runbook.md`). The DMS task then reads the CDC capture tables for ongoing replication.

## Swapping in an on-prem source

Point the DMS source endpoint at the on-prem host instead of this module's outputs; everything downstream (topics, jobs, tables) is unchanged. See `docs/architecture.md`.
