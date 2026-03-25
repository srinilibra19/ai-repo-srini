-- =============================================================================
-- V2__create_outbox_messages.sql
-- Flyway migration: outbox_messages table + LISTEN/NOTIFY trigger
--
-- The outbox table guarantees at-least-once delivery to SNS FIFO.
-- The outbox poller reads PENDING rows (SELECT ... FOR UPDATE SKIP LOCKED)
-- and publishes to SNS FIFO. On success, status transitions to PUBLISHED.
-- On failure, status transitions to FAILED; after max retries, to DLQ.
--
-- The NOTIFY trigger fires on every INSERT so the poller is woken immediately
-- rather than waiting for the 500ms fallback poll.
--
-- REQ-DB-011 compliance: all required columns present.
-- REQ-DB-012: trigger issues NOTIFY hermes_outbox_channel on each row insert.
-- REQ-DB-015: SKIP LOCKED supported by status index (poller queries status='PENDING').
-- =============================================================================

CREATE TABLE outbox_messages (
    id                  BIGSERIAL                NOT NULL,
    aggregate_id        VARCHAR(255),
    event_type          VARCHAR(100),
    payload             JSONB,
    destination_name    VARCHAR(512)             NOT NULL,
    target_sns_arn      VARCHAR(512)             NOT NULL,
    message_group_id    VARCHAR(128)             NOT NULL,
    deduplication_id    VARCHAR(128)             NOT NULL,
    status              VARCHAR(20)              NOT NULL DEFAULT 'PENDING',
    retry_count         INTEGER                  NOT NULL DEFAULT 0,
    error_message       TEXT,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    published_at        TIMESTAMP WITH TIME ZONE,

    CONSTRAINT outbox_messages_pkey             PRIMARY KEY (id),
    CONSTRAINT outbox_messages_dedup_id_unique  UNIQUE      (deduplication_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Hot-path query: WHERE status = 'PENDING' ORDER BY created_at (poller)
CREATE INDEX idx_outbox_messages_status_created_at
    ON outbox_messages (status, created_at)
    WHERE status IN ('PENDING', 'FAILED');

-- Destination-scoped queries (monitoring, per-destination dashboards)
CREATE INDEX idx_outbox_messages_destination_name
    ON outbox_messages (destination_name);

-- ---------------------------------------------------------------------------
-- NOTIFY trigger — fires on every row INSERT into outbox_messages
--
-- Sends NOTIFY on channel 'hermes_outbox_channel' with payload 'new'.
-- The OutboxPollerService maintains a LISTEN connection and immediately
-- calls pollAndPublish() when it receives this notification.
-- The 500ms @Scheduled fallback is a mandatory safety net (REQ-DB-012).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_outbox_notify()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    PERFORM pg_notify('hermes_outbox_channel', 'new');
    RETURN NEW;
END;
$$;

CREATE TRIGGER outbox_notify_trigger
    AFTER INSERT ON outbox_messages
    FOR EACH ROW                       -- fires per row, not per statement
    EXECUTE FUNCTION fn_outbox_notify();

-- ---------------------------------------------------------------------------
-- Comments — column-level documentation for DBA visibility
-- ---------------------------------------------------------------------------

COMMENT ON TABLE  outbox_messages                    IS 'Transactional outbox — guarantees at-least-once delivery from RDS to SNS FIFO';
COMMENT ON COLUMN outbox_messages.aggregate_id       IS 'Business correlation identifier (typically the Solace correlationId)';
COMMENT ON COLUMN outbox_messages.event_type         IS 'Event classification for downstream routing (e.g. FlightScheduleUpdated)';
COMMENT ON COLUMN outbox_messages.payload            IS 'SNS message payload (canonical JSON or ClaimCheckReference)';
COMMENT ON COLUMN outbox_messages.destination_name   IS 'Solace destination this message originated from (e.g. flightschedules/>)';
COMMENT ON COLUMN outbox_messages.target_sns_arn     IS 'Target SNS FIFO topic ARN for this outbox record';
COMMENT ON COLUMN outbox_messages.message_group_id   IS 'SNS FIFO MessageGroupId — controls ordering within the topic';
COMMENT ON COLUMN outbox_messages.deduplication_id   IS 'SNS FIFO MessageDeduplicationId — must be stable across retries (use Solace messageId)';
COMMENT ON COLUMN outbox_messages.status             IS 'Lifecycle state: PENDING | PUBLISHED | FAILED | DLQ';
COMMENT ON COLUMN outbox_messages.retry_count        IS 'Number of publish attempts (incremented on FAILED transitions)';
COMMENT ON COLUMN outbox_messages.error_message      IS 'Last SNS publish error detail — populated on FAILED and DLQ transitions';
COMMENT ON COLUMN outbox_messages.created_at         IS 'Row creation timestamp — immutable after insert; used for poller ordering';
COMMENT ON COLUMN outbox_messages.published_at       IS 'When the row was successfully published to SNS FIFO';
