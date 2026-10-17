# =============================================================================
# AWS provider configuration
#
# Credentials are never hardcoded. They come from the standard AWS provider
# chain (environment variables, shared credentials file, or an assumed role).
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
