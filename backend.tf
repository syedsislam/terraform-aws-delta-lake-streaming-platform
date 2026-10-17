# =============================================================================
# Remote state backend (S3 + DynamoDB lock)
#
# Partial backend configuration: the bucket, key, region and lock table are
# supplied at init time so the same code works across environments without
# hardcoding state locations. See backend.hcl.example and the Makefile.
#
#   terraform init -backend-config=backend.dev.hcl
# =============================================================================

terraform {
  backend "s3" {}
}
