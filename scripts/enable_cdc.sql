-- =============================================================================
-- Enable CDC on the RDS SQL Server source database.
--
-- RDS SQL Server enables Change Data Capture through msdb stored procedures,
-- which Terraform cannot invoke — run this script ONCE after `terraform apply`
-- (see docs/runbook.md). It enables CDC on the database and on each table
-- listed in the cdc_tables variable, capturing all columns.
--
-- Connect as the master user (credentials in Secrets Manager:
-- <project>-<environment>-sqlserver-credentials).
-- =============================================================================

USE [salesdb];
GO

-- Enable CDC on the database (creates the cdc schema, jobs and metadata tables)
EXEC msdb.dbo.rds_cdc_enable_db 'salesdb';
GO

-- Enable CDC on each replicated table. The capture instance name defaults to
-- <schema>_<table> (e.g. dbo_orders); DMS reads these capture tables.
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'orders',
    @role_name     = NULL,
    @supports_net_changes = 1;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'customers',
    @role_name     = NULL,
    @supports_net_changes = 1;
GO

EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'products',
    @role_name     = NULL,
    @supports_net_changes = 1;
GO

-- Verify
SELECT name, is_cdc_enabled FROM sys.databases WHERE name = 'salesdb';
SELECT s.name AS schema_name, t.name AS table_name, t.is_tracked_by_cdc
FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.name IN ('orders', 'customers', 'products');
GO
