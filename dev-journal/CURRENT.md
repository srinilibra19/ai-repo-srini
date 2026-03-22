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
- [x] ST-04: local-dev/setup.sh (Linux/macOS one-command setup) → DONE
- [x] ST-05: local-dev/setup.bat (Windows one-command setup) → DONE
- [x] ST-06: local-dev/verify.sh (Linux/macOS verification) → DONE
- [x] ST-07: local-dev/verify.bat (Windows verification) → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| local-dev/solace-init/provision-queues.sh | DONE | POSIX sh, semp_post() helper, DMQ first, idempotent via ALREADY_EXISTS |
| local-dev/docker-compose.yml | DONE | Added hermes-solace-init one-shot service with depends_on: service_healthy |
| README.md | DONE | SDKPerf section: 10 standard (1KB) messages + 5 large (250KB) messages |
| local-dev/setup.sh | DONE | Full setup: prereqs → .env → certs → compose up → health poll → verify |
| local-dev/setup.bat | DONE | Windows equivalent; includes Git Bash check for cert generation |
| local-dev/verify.sh | DONE | 5 sections: containers, Solace queues, LocalStack, PostgreSQL, SDKPerf |
| local-dev/verify.bat | DONE | Windows equivalent of verify.sh |

## Key Interfaces Defined
None — infrastructure provisioning, automation, and documentation only.

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| Shell script over Claude skill for automation | Deterministic, CI-friendly, runs without Claude | Claude skill (slow, non-deterministic, requires active session) |
| verify.sh/bat separate from setup.sh/bat | Testers can run verification without re-running full setup | Single monolithic script |
| SDKPERF_HOME env var for optional SDKPerf check | Not all developers have SDKPerf installed | Hard-fail if absent |
| Git Bash prerequisite in setup.bat | generate-certs.sh is a shell script, requires bash on Windows | PowerShell rewrite of cert generation |
| goto bash_found inside else block (setup.bat) | Known Low finding — accepted; does not affect core functionality | Refactor to temp file pattern (declined) |
| Specific grep patterns for queue names in verify.sh | Ambiguous grep would match DMQ line for main queue check | Generic loop (fixed from initial code review) |

## Accepted Deviations
| Item | Reason | User decision |
|------|--------|---------------|
| HTTP plaintext to Solace SEMP | Solace Standard Docker does not expose SEMP over HTTPS on port 8080 | Accepted 2026-03-22 |
| admin:admin hardcoded in provision-queues.sh | Canonical Solace Standard Docker default; local dev only | Accepted 2026-03-22 |
| verify.bat Low findings not fixed | temp file cleanup and variable init — Low severity, no functional impact | Declined 2026-03-22 |
| setup.bat goto label finding not fixed | Low severity, works on Windows 10/11 in practice | Declined 2026-03-22 |

## Exact Next Step
Begin US-E0-005: implement src/main/resources/application-local.yml — Spring Boot local profile pointing to Docker Compose services.

## Context to Load on Resume
Read these files (in order) before resuming — do not read anything else until these are loaded:
1. dev-journal/CURRENT.md (already reading this)
2. backlog.md — US-E0-005 block only
3. local-dev/docker-compose.yml (to confirm hostnames and ports for Solace, PostgreSQL, LocalStack)
CLAUDE.md sections needed: Java/Spring Boot standards, Solace/JCSMP standards, Security standards
