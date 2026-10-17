# Runbook: Deploy, Verify, Operate, Destroy

## 1. One-time bootstrap (per AWS account/region)

Terraform state needs a bucket and lock table *before* `init`:

```bash
aws s3api create-bucket --bucket my-tf-state-123456 --region us-east-1
aws s3api put-bucket-versioning --bucket my-tf-state-123456 \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name my-tf-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

Then:

```bash
cp backend.hcl.example backend.dev.hcl
# edit backend.dev.hcl with the bucket/table names above
```

If the account already has `dms-vpc-role` / `dms-cloudwatch-logs-role` (e.g. from console use), either delete them or `terraform import` them before apply — see troubleshooting.

## 2. Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # set environment + owner
make init ENV=dev
make plan ENV=dev     # review carefully
make apply ENV=dev
```

Module apply order is handled by `depends_on` in the root module; no manual `-target` needed.

## 3. Post-apply configuration

### 3a. Enable CDC on SQL Server (required before DMS CDC works)

```bash
# Fetch connection details (endpoint + creds never touch your shell history files)
aws secretsmanager get-secret-value \
  --secret-id <prefix>-dev-sqlserver-credentials --query SecretString --output text
```

Connect with `sqlcmd` (or SSMS) and run `scripts/enable_cdc.sql`. Verify with the trailing SELECTs: the database and all three tables must show CDC enabled.

### 3b. Subscribe to alarms

```bash
aws sns subscribe --topic-arn $(terraform output -raw alarm_sns_topic_arn) \
  --protocol email --notification-endpoint you@example.com
```

### 3c. Start the pipeline (order matters)

1. Confirm the DMS task is running: `aws dms describe-replication-tasks` → status `running`.
2. Start Glue jobs in layer order (each downstream job reads the upstream Delta tables):
   ```bash
   for job in bronze silver gold; do
     aws glue start-job-run --job-name <prefix>-dev-$job
   done
   ```

## 4. Verify end-to-end

1. **Source**: insert a row into `salesdb.dbo.orders`.
2. **MSK**: within a minute, the DMS task's `CDCLatencySource` should stay near zero and the topic `sqlserver.cdc.dbo.orders` should gain a message.
3. **Bronze**: `aws s3 ls s3://<lake-bucket>/bronze/dbo/orders/` shows new Delta files.
4. **Silver/gold**: query via Athena against the `<prefix>_dev_lake` database:
   ```sql
   SELECT * FROM bronze_orders ORDER BY _ingest_ts DESC LIMIT 5;
   SELECT * FROM gold_hourly_revenue ORDER BY window_start DESC LIMIT 5;
   ```
5. **Dashboard**: open `<prefix>-dev-pipeline` in CloudWatch.

## 5. Operate

- **Replay a layer**: delete the layer's Delta path (versioned, so recoverable) and its `checkpoints/<job>/` prefix, then restart the job. Bronze replays from Kafka retention; silver/gold rebuild from bronze.
- **Backfill a new table**: add it to `cdc_tables`, `terraform apply`, enable CDC for it, restart jobs.
- **Rotate the DMS SCRAM secret**: update the Secrets Manager value, then update the DMS Kafka endpoint's SASL password (console or `modify-endpoint`) and restart the task.
- **Scale**: raise `glue_workers` / `msk_ebs_volume_size` in the `.tfvars` and apply; MSK storage autoscaling handles disk emergencies automatically.

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform apply` fails: DMS roles already exist | Roles created previously via console | `terraform import aws_iam_role.dms_vpc dms-vpc-role` (same for logs role) |
| DMS task stuck in `creating` | Endpoints not reachable | Check DMS SG → RDS SG (1433) and DMS SG → MSK SG (9098); verify CDC enabled |
| Bronze empty, DMS running | Topic name mismatch | Confirm topics are `sqlserver.cdc.<schema>.<table>`; check DMS table-mapping rename rules |
| Glue job fails: `ClassNotFoundException: DeltaSparkSessionExtension` | Delta jar not resolved | Check NAT gateway route; or stage the jar in the scripts bucket and set `--extra-jars` |
| Glue job fails: SASL auth error to MSK | IAM auth misconfigured | Verify the job role's `kafka-cluster:*` permissions and the MSK IAM auth library in `--conf spark.jars.packages` |
| Silver not updating | Checkpoint corruption after schema change | Delete `checkpoints/silver/...` and restart (replay from bronze) |
| `CDCLatencySource` alarm firing | Source transaction log pressure or DMS under-provisioned | Check RDS free storage; consider a larger `dms_instance_class` |

## 7. Destroy

```bash
# Stop streaming jobs first so no new checkpoints are written mid-destroy
for job in gold silver bronze; do
  aws glue batch-stop-job-run --job-name <prefix>-dev-$job \
    --job-run-ids $(aws glue get-job-runs --job-name <prefix>-dev-$job \
      --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text)
done
make destroy ENV=dev
```

Notes: RDS has deletion protection on — `terraform destroy` will fail until you set `deletion_protection = false` (dev) or remove it deliberately. S3 buckets must be empty; the versioned lake bucket may need `aws s3 rm --recursive` first. The state bucket/table are *not* managed by this configuration and survive destroy.
