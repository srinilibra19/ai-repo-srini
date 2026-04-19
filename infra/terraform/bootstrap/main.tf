# =============================================================================
# Bootstrap — Terraform remote state backend provisioning
#
# Run this module ONCE to create the S3 bucket and DynamoDB lock table that
# all other Terraform environments will use as their remote backend.
#
# Step 1 — Apply with local state (first run):
#   cd infra/terraform/bootstrap
#   terraform init
#   terraform apply -var="owner=<team>" -var="cost_center=<code>"
#
# Step 2 — Migrate bootstrap state into the bucket it just created:
#   terraform init -migrate-state \
#     -backend-config="bucket=$(terraform output -raw state_bucket_name)" \
#     -backend-config="key=bootstrap/terraform.tfstate" \
#     -backend-config="region=$(var.aws_region)" \
#     -backend-config="dynamodb_table=hermes-terraform-locks" \
#     -backend-config="encrypt=true"
#
# After migration the bootstrap state is stored in the same bucket under the
# key "bootstrap/terraform.tfstate". All other environments use separate keys:
#   environments/staging/terraform.tfstate
#   environments/prod/terraform.tfstate
# =============================================================================

terraform {
  required_version = ">= 1.14.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local backend intentionally — this module bootstraps the remote backend.
  # After first apply, run `terraform init -migrate-state` (see header above).
  backend "local" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "hermes-terraform-state-${local.account_id}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Destination = "platform"
  }
}

# =============================================================================
# KMS CMK — encrypts the state bucket and lock table
#
# Separate from the application KMS keys (US-E1-004) because this key must
# exist before any other module runs. Rotation enabled per CLAUDE.md.
# =============================================================================

resource "aws_kms_key" "terraform_state" {
  description             = "KMS CMK for Hermes Terraform state S3 bucket and DynamoDB lock table"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "hermes-terraform-state-key"
  })
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/hermes-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# =============================================================================
# S3 bucket — Terraform remote state storage
# =============================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# =============================================================================
# DynamoDB table — Terraform state locking
#
# PAY_PER_REQUEST: state lock acquisitions are rare; provisioned capacity
# would be wasteful. PITR enabled for recovery from accidental table deletion.
# =============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "hermes-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  tags = merge(local.common_tags, {
    Name = "hermes-terraform-locks"
  })
}
