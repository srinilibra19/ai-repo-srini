# Active Story Handoff
Last updated : 2026-03-23T02:00:00
Story        : US-E0-005 — Spring Boot application-local.yml
Status       : NOT STARTED
Sprint       : 1

## Previous Story Completed
US-E0-004 — Solace local queue and subscription provisioning — COMPLETE
Local stack confirmed healthy on Windows 2026-03-23. All 13 verify.bat checks pass.

## Fixes Applied During Local Stack Run (2026-03-23)
| File | Fix | Root Cause |
|------|-----|------------|
| local-dev/docker-compose.yml | shm_size: 256m → 1g | Solace requires 1000 MB /dev/shm |
| local-dev/docker-compose.yml | nofile hard: 38048 → 1048576 | Solace POST Violation [022]: requires 1048576 |
| local-dev/docker-compose.yml | curlimages/curl:8 → curlimages/curl:8.12.1 | Tag :8 does not exist on Docker Hub |
| local-dev/localstack-init/bootstrap.sh | Added AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY/DEFAULT_REGION env vars | AWS CLI requires credentials even for LocalStack |
| local-dev/localstack-init/bootstrap.sh | Replaced --no-cli-pager with AWS_PAGER="" | --no-cli-pager is CLI v2 only; LocalStack ships CLI v1 |
| local-dev/localstack-init/bootstrap.sh | Replaced --attributes shorthand for set-queue-attributes with python3 JSON encoding | CLI v1 shorthand parser cannot handle quoted JSON values in --attributes |
| local-dev/verify.bat | Escaped check^(s^) in else block | ) in check(s) closed the else ( block prematurely |
| local-dev/certs/generate-certs.sh | Added MSYS_NO_PATHCONV=1 + cygpath -m for OUT_W | MSYS2 auto-converts /CN= to Windows path; native binaries need Windows-style paths |
| local-dev/certs/generate-certs.sh | CA key 4096 → 2048 bits | 4096-bit key generation hangs on Windows (entropy issue) |
| local-dev/setup.bat | goto-based skip replacing if/else block for bash check | CMD label inside parenthesised if/else block causes ": was unexpected at this time." |
| local-dev/setup.bat | Derive GIT_BASH_EXE from git.exe path instead of bare bash | WSL relay bash on PATH is non-functional for running shell scripts |

## US-E0-005 Acceptance Criteria
- [ ] src/main/resources/application-local.yml created with all local Docker Compose settings
- [ ] Solace connection: tcp://localhost:55555 (plaintext) with admin/admin credentials
- [ ] PostgreSQL: localhost:5432 db=hermes user=hermes password=hermes
- [ ] LocalStack SNS/SQS: endpoint http://localhost:4566, region us-east-1, dummy credentials
- [ ] Flyway migrations enabled and pointing to local PostgreSQL
- [ ] Spring profile: local
- [ ] No secrets in the file — only local dev defaults that match docker-compose.yml

## Context to Load on Resume
Read these files (in order) before resuming:
1. dev-journal/CURRENT.md (already reading this)
2. backlog.md — US-E0-005 acceptance criteria
3. src/main/resources/application.yml — base config to understand what local overrides
CLAUDE.md sections needed: Java/Spring Boot standards, Solace/JCSMP standards, Security standards
