-- =============================================================================
-- V3__create_indexes.sql
-- Flyway migration: supplementary indexes for audit_messages and outbox_messages
--
-- Indexes in V1 and V2 cover the primary operational queries (idempotency lookup,
-- outbox poller, status queries). This migration adds supplementary indexes for:
--   - SNS message ID lookup (audit table — post-publish correlation)
--   - DLQ sweep queries (both tables — operations and alerting)
--   - Payload size range queries (audit table — claim-check monitoring)
--   - Published_at range queries (outbox table — latency monitoring)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- audit_messages supplementary indexes
-- ---------------------------------------------------------------------------

-- SNS confirmation ID lookup — used to correlate SNS delivery receipts back to
-- audit rows. Partial index: only rows where sns_message_id IS NOT NULL, which
-- is the subset that has been published. Keeps the index small.
CREATE INDEX idx_audit_messages_sns_message_id
    ON audit_messages (sns_message_id)
    WHERE sns_message_id IS NOT NULL;

-- Consumer group + status composite — used for per-Deployment health queries:
-- "how many messages is hermes-flightschedules-pod-X currently PROCESSING?"
CREATE INDEX idx_audit_messages_consumer_group_status
    ON audit_messages (consumer_group, status);

-- Payload size range — used by the claim-check monitoring dashboard to identify
-- messages that triggered S3 upload (payload_size_bytes > 204800).
CREATE INDEX idx_audit_messages_payload_size_bytes
    ON audit_messages (payload_size_bytes)
    WHERE payload_size_bytes > 204800;

-- ---------------------------------------------------------------------------
-- outbox_messages supplementary indexes
-- ---------------------------------------------------------------------------

-- Published_at range — used for outbox latency monitoring:
-- time between created_at and published_at is the end-to-end outbox latency.
-- Partial index: only rows where published_at IS NOT NULL (PUBLISHED rows).
CREATE INDEX idx_outbox_messages_published_at
    ON outbox_messages (published_at)
    WHERE published_at IS NOT NULL;

-- DLQ sweep — used by the operations runbook to identify messages requiring
-- manual intervention. Partial index: DLQ rows only (small, terminal set).
CREATE INDEX idx_outbox_messages_dlq
    ON outbox_messages (created_at)
    WHERE status = 'DLQ';

-- Aggregate ID lookup — used to find all outbox rows related to a given
-- business correlation ID (e.g. tracing a flight schedule update end-to-end).
-- Partial index: only rows where aggregate_id IS NOT NULL.
CREATE INDEX idx_outbox_messages_aggregate_id
    ON outbox_messages (aggregate_id)
    WHERE aggregate_id IS NOT NULL;
