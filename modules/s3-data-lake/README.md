# s3-data-lake

S3 storage for the Delta Lake medallion architecture.

## Buckets

| Bucket | Contents | Protection |
|---|---|---|
| `<project>-<env>-data-lake-<suffix>` | `bronze/`, `silver/`, `gold/`, `checkpoints/`, `_tmp/` | Versioning, KMS, lifecycle, access logging, public access blocked |
| `<project>-<env>-glue-scripts-<suffix>` | Versioned Glue job `.py` files under `glue-jobs/` | Versioning, KMS, public access blocked |

## Lifecycle policy

- `bronze/` → STANDARD_IA after N days → GLACIER after 4N (raw data is rarely re-read but must be retained for replays).
- `checkpoints/` expire after 90 days; `_tmp/` after 7 days — operational data, not analytical.
- Incomplete multipart uploads are aborted after 7 days (streaming writes can leave these behind).

## Deployment note

`aws_s3_object.glue_scripts` uploads `glue-jobs/*.py` from the repo at apply time, keyed by content hash — the jobs always run the committed code, and a script change shows up in `terraform plan` as a re-upload.
