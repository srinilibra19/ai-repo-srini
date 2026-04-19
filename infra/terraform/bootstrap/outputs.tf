output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state. Use in -backend-config=\"bucket=<value>\"."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for state locking. Use in -backend-config=\"dynamodb_table=<value>\"."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table."
  value       = aws_dynamodb_table.terraform_locks.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK used to encrypt the state bucket and lock table."
  value       = aws_kms_key.terraform_state.arn
}

output "kms_key_alias" {
  description = "Alias of the state bucket KMS CMK."
  value       = aws_kms_alias.terraform_state.name
}

output "backend_init_command_staging" {
  description = "terraform init command for the staging environment. Copy and run from infra/terraform/environments/staging/."
  value       = <<-EOT
    terraform init \
      -backend-config="bucket=${aws_s3_bucket.terraform_state.bucket}" \
      -backend-config="key=environments/staging/terraform.tfstate" \
      -backend-config="region=${var.aws_region}" \
      -backend-config="dynamodb_table=${aws_dynamodb_table.terraform_locks.name}" \
      -backend-config="encrypt=true" \
      -backend-config="kms_key_id=${aws_kms_key.terraform_state.arn}"
  EOT
}

output "backend_init_command_prod" {
  description = "terraform init command for the prod environment. Copy and run from infra/terraform/environments/prod/."
  value       = <<-EOT
    terraform init \
      -backend-config="bucket=${aws_s3_bucket.terraform_state.bucket}" \
      -backend-config="key=environments/prod/terraform.tfstate" \
      -backend-config="region=${var.aws_region}" \
      -backend-config="dynamodb_table=${aws_dynamodb_table.terraform_locks.name}" \
      -backend-config="encrypt=true" \
      -backend-config="kms_key_id=${aws_kms_key.terraform_state.arn}"
  EOT
}
