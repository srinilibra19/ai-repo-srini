# Active Story Handoff
Last updated : 2026-03-25
Story        : US-E3-003 — Database schema migration — outbox_messages table with LISTEN/NOTIFY trigger
Status       : COMPLETE
Sprint       : 3

## Acceptance Criteria Status
- [x] Flyway migration V2__create_outbox_messages.sql creates table with all REQ-DB-011 columns
- [x] Index on status, created_at
- [x] PostgreSQL trigger outbox_notify_trigger on INSERT executes NOTIFY hermes_outbox_channel, 'new'
- [x] Trigger fires for each inserted row (not per statement)
- [x] Flyway migration V3__create_indexes.sql adds supplementary indexes

## Sub-task Status
- [x] ST-01: V2__create_outbox_messages.sql → DONE
- [x] ST-02: OutboxMessage.java JPA entity → DONE
- [x] ST-03: OutboxMessageRepository.java → DONE
- [x] ST-04: OutboxMessageRepositoryTest.java → DONE
- [x] ST-05: V3__create_indexes.sql → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| src/main/resources/db/migration/V2__create_outbox_messages.sql | DONE | outbox_notify_trigger FOR EACH ROW, UNIQUE on deduplication_id |
| src/main/java/com/middleware/hermes/model/entity/OutboxMessage.java | DONE | @Enumerated STRING, @Builder.Default, @Generated(INSERT) on createdAt |
| src/main/java/com/middleware/hermes/repository/OutboxMessageRepository.java | DONE | SKIP LOCKED native queries, @Modifying(clearAutomatically=true) |
| src/test/java/com/middleware/hermes/unit/repository/OutboxMessageRepositoryTest.java | DONE | 10 tests — all status transitions covered |
| src/main/resources/db/migration/V3__create_indexes.sql | DONE | 6 supplementary partial indexes |

## Next Story
US-E3-004 — HikariCP connection pool configuration
Per Path B: E3-003 → E3-004 → E5-002

## Context to Load on Resume
1. dev-journal/CURRENT.md (already reading)
2. dev-journal/progress-index.md — confirm E3-004 is next
3. backlog.md — E3-004 story block only
CLAUDE.md sections needed: Java/Spring Boot standards, HikariCP config
