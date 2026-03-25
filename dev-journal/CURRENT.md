# Active Story Handoff
Last updated : 2026-03-25
Story        : US-E3-002 — Database schema migration — audit_messages table
Status       : COMPLETE
Sprint       : 3

## Acceptance Criteria Status
- [x] Flyway migration V1__create_audit_messages.sql creates table with all REQ-DB-007 columns
- [x] UNIQUE constraint on message_id
- [x] Indexes: message_id (unique via constraint), status, created_at, source_destination, correlation_id
- [x] Default values: status='RECEIVED', retry_count=0, created_at=NOW(), updated_at=NOW()
- [x] Trigger update_audit_messages_updated_at updates updated_at on every row update
- [x] Migration runs automatically on application startup via Spring Boot Flyway auto-configuration
- [x] Flyway baseline applied to existing databases (spring.flyway.baseline-on-migrate=true)

## Sub-task Status
- [x] ST-01: V1__create_audit_messages.sql → DONE
- [x] ST-02: AuditMessage.java JPA entity → DONE
- [x] ST-03: OutboxStatus.java enum → DONE
- [x] ST-04: AuditMessageRepository.java → DONE
- [x] ST-05: AuditMessageRepositoryTest.java + OutboxStatusTest.java → DONE
- [x] ST-06: application.yml baseline-on-migrate=true → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| src/main/resources/db/migration/V1__create_audit_messages.sql | DONE | 17 columns, UNIQUE constraint, 4 indexes, updated_at trigger |
| src/main/java/com/middleware/hermes/model/entity/AuditMessage.java | DONE | @Generated timestamps, @JdbcTypeCode JSONB, @Builder.Default retryCount=0 |
| src/main/java/com/middleware/hermes/model/OutboxStatus.java | DONE | PENDING, PUBLISHED, FAILED, DLQ |
| src/main/java/com/middleware/hermes/repository/AuditMessageRepository.java | DONE | @Modifying(clearAutomatically=true) @Transactional on updateStatus |
| src/test/java/com/middleware/hermes/unit/repository/AuditMessageRepositoryTest.java | DONE | 9 tests — happy + failure paths |
| src/test/java/com/middleware/hermes/unit/model/OutboxStatusTest.java | DONE | 8 tests — constants, valueOf, case-sensitivity |
| src/main/resources/application.yml | MODIFIED | baseline-on-migrate: true |

## Next Story
US-E3-003 — Database schema migration (outbox_messages table + LISTEN/NOTIFY trigger)
Per Path B decision: E5-001 → E3-002 → E3-003 → E5-002

## Context to Load on Resume
1. dev-journal/CURRENT.md (already reading)
2. dev-journal/progress-index.md — confirm E3-003 is next
3. backlog.md — E3-003 story block only (REQ-DB-011 columns)
CLAUDE.md sections needed: Java/Spring Boot standards, SQL migration standards, Transactional Outbox standards
