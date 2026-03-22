# Active Story Handoff
Last updated : 2026-03-22T00:00:00
Story        : US-E0-004 — Solace local queue and subscription provisioning
Status       : COMPLETE
Sprint       : 1

## Acceptance Criteria Status
- [x] SEMPv2 init script provisions: queue hermes.flightschedules (non-exclusive, 4GB spool), topic subscription flightschedules/>, DMQ hermes.flightschedules.dmq
- [x] Init script runs on Solace container startup (hermes-solace-init one-shot service, depends_on: service_healthy)
- [x] SDKPerf command documented in README to publish 10 test messages to flightschedules/events
- [x] Test publisher can publish messages of variable size (including >200 KB)

## Sub-task Status
- [x] ST-01: provision-queues.sh → DONE
- [x] ST-02: docker-compose.yml hermes-solace-init service → DONE
- [x] ST-03: README.md SDKPerf documentation → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| local-dev/solace-init/provision-queues.sh | DONE | POSIX sh, semp_post() helper, DMQ first, idempotent via ALREADY_EXISTS |
| local-dev/docker-compose.yml | DONE | Added hermes-solace-init one-shot service with depends_on: service_healthy |
| README.md | DONE | SDKPerf section: 10 standard (1KB) messages + 5 large (250KB) messages |

## Key Interfaces Defined
None — infrastructure provisioning and documentation only.

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| POSIX sh in curlimages/curl:8 | Only curl available; no bash in Alpine-based image | bash (not available), separate Python container |
| DMQ created before main queue | deadMsgQueue attribute must reference an existing queue | Create main queue first (would fail reference) |
| maxDeliveredUnackedMsgsPerFlow: 32 | Aligns with JCSMP sub-ack-window-size standard | Higher values (not load-tested) |
| hermes-solace-init one-shot service | Solace Standard has no native init hook unlike LocalStack | Polling loop inside Solace container |
| grep -q '"ALREADY_EXISTS"' for idempotency | Solace SEMPv2 returns string code, not numeric | grep for numeric code field (wrong — would never match) |

## Accepted Deviations
| Item | Reason | User decision |
|------|--------|---------------|
| HTTP plaintext to Solace SEMP | Solace Standard Docker does not expose SEMP over HTTPS on port 8080 | Accepted 2026-03-22 |
| admin:admin hardcoded in provision-queues.sh | Canonical Solace Standard Docker default; local dev only | Accepted 2026-03-22 |

## Exact Next Step
Begin US-E0-005: implement src/main/resources/application-local.yml — Spring Boot local profile pointing to Docker Compose services.

## Context to Load on Resume
Read these files (in order) before resuming — do not read anything else until these are loaded:
1. dev-journal/CURRENT.md (already reading this)
2. backlog.md — US-E0-005 block only
3. local-dev/docker-compose.yml (to confirm hostnames and ports for Solace, PostgreSQL, LocalStack)
CLAUDE.md sections needed: Java/Spring Boot standards, Solace/JCSMP standards, Security standards
