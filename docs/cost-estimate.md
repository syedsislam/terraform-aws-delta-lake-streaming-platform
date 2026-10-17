# Cost Estimate (us-east-1, on-demand, ~730h/month)

Estimates only — verify with the AWS Pricing Calculator before budgeting. Data transfer and S3 request charges scale with actual CDC volume.

## dev (environments/dev.tfvars)

| Component | Spec | ≈ $/mo |
|---|---|---|
| MSK (3× kafka.t3.small, 50 GB) | brokers + storage | 150 |
| RDS SQL Server SE (db.t3.medium, 50 GB, single-AZ) | includes SE license | 180 |
| DMS (dms.t3.medium) | replication instance | 90 |
| Glue streaming (3 jobs × 2× G.1X workers) | ~$0.44/DPU-h × 12 DPUs | 120 |
| S3 (lake + scripts, small volume) | storage + requests | 10 |
| NAT gateway + CloudWatch + KMS + Secrets Manager | | 45 |
| **Total** | | **≈ $595** |

## prod (environments/prod.tfvars)

| Component | Spec | ≈ $/mo |
|---|---|---|
| MSK (3× kafka.m5.large, 200 GB) | brokers + storage | 620 |
| RDS SQL Server SE (db.m5.large, 200 GB, Multi-AZ) | includes SE license | 620 |
| DMS (dms.c5.large, Multi-AZ) | replication instance | 350 |
| Glue streaming (3 jobs × 8× G.2X workers) | ~$0.88/DPU-h × 48 DPUs | 620 |
| S3 (lake + scripts, moderate volume) | storage + requests | 40 |
| NAT gateway + CloudWatch + KMS + Secrets Manager | | 60 |
| **Total** | | **≈ $2,310** |

## Biggest levers

1. **Glue workers** dominate the variable cost — right-size with autoscaling metrics before raising counts.
2. **RDS SQL Server SE** license is the largest fixed cost; for a pure demo, Express edition (or a containerised source) cuts it dramatically.
3. **Dev exists to be destroyed**: `make destroy ENV=dev` after each demo session; state survives in S3.
4. MSK storage autoscaling and S3 lifecycle tiering prevent the two classic cost surprises (full broker disks, ever-growing bronze).
