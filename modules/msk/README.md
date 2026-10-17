# msk

Amazon MSK (provisioned) cluster buffering CDC events between DMS and Glue.

## Security posture

- **Client auth: IAM (SASL) over TLS for Glue** — role-based, nothing to rotate.
- **Client auth: SCRAM over TLS for the DMS producer** — AWS DMS Kafka targets do not support MSK IAM access control, so a SCRAM credential (Secrets Manager + cluster association) is provisioned for DMS. Rotation = update the secret and the DMS endpoint.
- **Encryption at rest** with a dedicated KMS key (independent from the S3 key).
- **No plaintext listeners** — `unauthenticated = false`, in-transit encryption enforced.

## Operations

- `PER_TOPIC_PER_BROKER` enhanced monitoring feeds the consumer-lag alarms in the `monitoring` module.
- Prometheus JMX + node exporters are enabled for deeper broker introspection.
- Storage autoscaling (target 60% disk use) protects against CDC backlogs filling the brokers.
- Topic auto-creation is **enabled** because DMS requires it to materialise the CDC topics on first produce; topic *names* are still fully controlled by the DMS table-mapping rename rules.
- Default topic settings: 6 partitions, replication factor 3, `min.insync.replicas=2`, 7-day retention.

## Topic naming

`sqlserver.cdc.<schema>.<table>` (e.g. `sqlserver.cdc.dbo.orders`), built by the DMS table-mapping rules in the `dms` module.
