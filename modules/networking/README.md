# networking

Purpose-built VPC for the streaming data platform.

## What it creates

| Resource | Purpose |
|---|---|
| VPC + 3 AZs | Isolation boundary for every data-plane workload |
| Public / private subnets | NAT lives in public; MSK, RDS, DMS and Glue ENIs live in private |
| NAT gateway | Outbound internet for DMS/Glue (patching, package downloads) |
| S3 gateway endpoint | Data-lake traffic never leaves the AWS network |
| Glue interface endpoint | Private Glue API access from the jobs |
| 4 security groups | Least-privilege port rules: MSK (9098 from DMS/Glue), RDS (1433 from DMS), DMS, Glue (self-referencing) |
| Glue NETWORK connection | Lets Glue streaming jobs attach ENIs in the private subnets |

## Design notes

- **One NAT gateway** (not one per AZ) keeps dev costs down; promote to per-AZ NAT in prod if the NAT becomes a bottleneck or single point of failure.
- Security groups reference each other (not CIDR ranges) so rules stay correct when subnets change.
- The Glue security group is self-referencing, which AWS requires for Glue ENI-to-ENI traffic.
