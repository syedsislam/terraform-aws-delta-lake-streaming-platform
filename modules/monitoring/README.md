# monitoring

Observability for the streaming platform.

## What it creates

- CloudWatch log group for MSK broker logs (referenced by the `msk` module).
- SNS topic for all alarm notifications — subscribe an email or PagerDuty endpoint after apply.
- Alarms:
  - MSK broker CPU > 80%; under-replicated partitions > 0.
  - DMS `CDCLatencySource` > 5 min — the earliest signal that the pipeline is falling behind the source.
  - Glue streaming job failed tasks > 0 (one alarm per job).
  - RDS CPU > 80%; free storage < 20 GiB.
- A CloudWatch dashboard with MSK, DMS latency, and RDS widgets.

## After apply

Subscribe to the SNS topic (`<prefix>-alarms`) — alarms go nowhere until someone listens. In prod, wire it to PagerDuty/OpsGenie rather than email.
