# =============================================================================
# backend.tf — Root Terraform module remote state configuration
#
# This file is a partial backend configuration. Account-specific values
# (bucket name, KMS key ARN) are injected at `terraform init` time via
# -backend-config flags or a gitignored backend.hcl file. This keeps
# account IDs out of version control while still committing the stable
# fields (key path, region, table name, encrypt flag).
#
# PREREQUISITES: Run the bootstrap module first to create the S3 bucket
# and DynamoDB lock table. The bootstrap outputs the exact init command:
#
#   cd infra/terraform/bootstrap
#   terraform init
#   terraform apply -var="owner=<team>" -var="cost_center=<code>"
#   terraform output backend_init_command_staging
#
# Then initialise this root module:
#
#   cd infra/terraform
#   terraform init \
#     -backend-config="bucket=hermes-terraform-state-<account-id>" \
#     -backend-config="kms_key_id=<kms-key-arn-from-bootstrap-output>"
#
# Or create a gitignored backend.hcl:
#   echo 'bucket     = "hermes-terraform-state-<account-id>"'  >> backend.hcl
#   echo 'kms_key_id = "<kms-key-arn>"'                        >> backend.hcl
#   terraform init -backend-config=backend.hcl
# =============================================================================

terraform {
  required_version = ">= 1.14.7"

  backend "s3" {
    key            = "root/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "hermes-terraform-locks"
    encrypt        = true
    # bucket and kms_key_id supplied via -backend-config at terraform init
  }
}
