# =============================================================================
# backend.tf — Staging environment remote state
#
# Partial configuration — account-specific values injected at init time:
#
#   cd infra/terraform/environments/staging
#   terraform init \
#     -backend-config="bucket=hermes-terraform-state-<account-id>" \
#     -backend-config="kms_key_id=<kms-key-arn-from-bootstrap-output>"
#
# Or use a gitignored backend.hcl file in this directory.
# The bootstrap output `backend_init_command_staging` prints the full command.
# =============================================================================

terraform {
  required_version = ">= 1.14.7"

  backend "s3" {
    key            = "environments/staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "hermes-terraform-locks"
    encrypt        = true
    # bucket and kms_key_id supplied via -backend-config at terraform init
  }
}
