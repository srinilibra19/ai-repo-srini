# Active Story Handoff
Last updated : 2026-04-19
Story        : US-E1-001 — Terraform remote state backend
Status       : COMPLETE
Sprint       : 1

## Acceptance Criteria Status
- [x] S3 bucket `hermes-terraform-state-{account-id}` with versioning, encryption (KMS), and public access blocked
- [x] DynamoDB table `hermes-terraform-locks` for state locking
- [x] `backend.tf` configured to use S3 backend
- [x] Bootstrap script `infra/terraform/bootstrap/` provisions state bucket and lock table using local state initially, then migrates
- [x] Separate state per environment using separate state keys (staging / prod)

## Sub-task Status
- [x] ST-01: Bootstrap module (S3 + DynamoDB + KMS) → DONE
- [x] ST-02: backend.tf configs (root + staging + prod) → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| infra/terraform/bootstrap/main.tf | DONE | KMS CMK, S3 bucket (versioning, SSE, public-access-block, TLS policy), DynamoDB table (PITR, SSE) |
| infra/terraform/bootstrap/variables.tf | DONE | aws_region, project, environment, owner, cost_center |
| infra/terraform/bootstrap/outputs.tf | DONE | Bucket name/ARN, table name/ARN, KMS ARN/alias, init commands for staging + prod |
| infra/terraform/backend.tf | DONE | Partial S3 backend — key=root/terraform.tfstate |
| infra/terraform/environments/staging/backend.tf | DONE | Partial S3 backend — key=environments/staging/terraform.tfstate |
| infra/terraform/environments/prod/backend.tf | DONE | Partial S3 backend — key=environments/prod/terraform.tfstate |

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| Separate state keys per env | Per-env IAM scoping on state bucket; staging CI cannot read prod state | Workspaces (shared key prefix, harder to IAM-scope) |
| KMS key in bootstrap module | Bootstrap must be self-contained; can't depend on US-E1-004 which creates app KMS keys | Reuse US-E1-004 key (creates circular dependency) |
| Partial backend config pattern | Account ID and KMS ARN not hardcoded in Git; injected at terraform init | Full config in Git (exposes account ID) |
| PAY_PER_REQUEST for DynamoDB | State lock acquisitions are rare; provisioned capacity wasteful | PROVISIONED (unnecessary cost) |

## Exact Next Step
Story complete. Next story: US-E1-002 — VPC and networking module.
