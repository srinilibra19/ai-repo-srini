# Active Story Handoff
Last updated : 2026-03-22T00:00:00
Story        : US-E0-003 — LocalStack initialisation for SNS FIFO and SQS FIFO
Status       : COMPLETE
Sprint       : 1

## Acceptance Criteria Status
- [x] LocalStack init script creates: hermes-flightschedules.fifo SNS FIFO topic; hermes-flightschedules-consumer-a.fifo SQS FIFO queue; hermes-flightschedules-dlq.fifo SQS DLQ FIFO queue
- [x] SNS subscription from topic to SQS queue is configured (raw message delivery, SQS access policy)
- [x] S3 bucket hermes-claim-check-local is created for large message payloads (public access blocked)
- [x] LocalStack Secrets Manager contains test Solace credentials and cert paths
- [x] Init script runs automatically on docker compose up (via LocalStack init/ready.d mechanism)

## Sub-task Status
- [x] ST-01: bootstrap.sh → DONE
- [x] ST-02: docker-compose.yml LocalStack mount → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| local-dev/localstack-init/bootstrap.sh | DONE | SNS FIFO, SQS FIFO, DLQ, S3, Secrets Manager; idempotent |
| local-dev/docker-compose.yml | DONE | Added ./localstack-init:/etc/localstack/init/ready.d:ro |

## Key Interfaces Defined
None — infrastructure provisioning script only.

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| LocalStack init/ready.d mechanism | Native to LocalStack 4.x, no extra container | Separate one-shot service with depends_on |
| aws_cmd() wrapper function | Eliminates repetition of endpoint/region/format flags | Inline flags on every call |
| delete-force + recreate for Secrets Manager | Secrets Manager create-secret not idempotent | Check-then-create (more complex) |
| SQS redrive policy set after queue creation | Avoids bash quoting issues with inline nested JSON | Inline in create-queue attributes |

## Accepted Deviations
| Item | Reason | User decision |
|------|--------|---------------|
| Multi-line JSON heredoc in CLI --attributes | Functional for local dev; python3 compaction adds complexity | Accepted 2026-03-22 |
| HTTP plaintext to LocalStack | LocalStack community limitation | Accepted 2026-03-22 |
| Local dev credentials in git-tracked script | Consistent with .env.example accepted pattern | Accepted 2026-03-22 |

## Exact Next Step
Begin US-E0-004: implement local-dev/solace-init/provision-queues.sh — SEMPv2 queue and topic subscription provisioning.

## Context to Load on Resume
Read these files (in order) before resuming — do not read anything else until these are loaded:
1. dev-journal/CURRENT.md (already reading this)
2. local-dev/docker-compose.yml (to understand Solace container hostname and admin credentials)
3. backlog.md — US-E0-004 block only
CLAUDE.md sections needed: Local Dev Quick Reference
