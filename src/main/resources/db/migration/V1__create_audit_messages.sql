-- =============================================================================
-- V1__create_audit_messages.sql
-- Flyway migration: audit_messages table
--
-- Every Solace message received by Hermes is recorded here with full lifecycle
-- tracking from RECEIVED through PUBLISHED (or FAILED / DLQ).
--
-- REQ-DB-007 compliance: all required columns, types, constraints, and defaults.
-- =============================================================================

CREATE TABLE audit_messages (
    id                  BIGSERIAL                NOT NULL,
    message_id          VARCHAR(255)             NOT NULL,
    correlation_id      VARCHAR(255),
    source_destination  VARCHAR(512)             NOT NULL,
    consumer_group      VARCHAR(255)             NOT NULL,
    message_payload     JSONB,
    payload_size_bytes  INTEGER                  NOT NULL,
    payload_hash        VARCHAR(64),
    sns_message_id      VARCHAR(255),
    sns_topic_arn       VARCHAR(512),
    status              VARCHAR(50)              NOT NULL DEFAULT 'RECEIVED',
    retry_count         INTEGER                  NOT NULL DEFAULT 0,
    error_message       TEXT,
    received_at         TIMESTAMP WITH TIME ZONE NOT NULL,
    processed_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT audit_messages_pkey        PRIMARY KEY (id),
    CONSTRAINT audit_messages_message_id  UNIQUE      (message_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
-- Note: message_id unique index is created implicitly by the UNIQUE constraint
-- above. No separate CREATE UNIQUE INDEX needed for that column.

-- Status-based queries: poller, monitoring, DLQ sweep
CREATE INDEX idx_audit_messages_status
    ON audit_messages (status);

-- Time-range queries: CloudWatch dashboards, runbook investigation
CREATE INDEX idx_audit_messages_created_at
    ON audit_messages (created_at);

-- Per-destination audit queries
CREATE INDEX idx_audit_messages_source_destination
    ON audit_messages (source_destination);

-- Business correlation lookups
CREATE INDEX idx_audit_messages_correlation_id
    ON audit_messages (correlation_id)
    WHERE correlation_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- updated_at trigger — keeps updated_at current on every row modification
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_update_audit_messages_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS
$$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER update_audit_messages_updated_at
    BEFORE UPDATE ON audit_messages
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_audit_messages_updated_at();

-- ---------------------------------------------------------------------------
-- Comments — column-level documentation for DBA visibility
-- ---------------------------------------------------------------------------

COMMENT ON TABLE  audit_messages                    IS 'Full audit record for every Solace message received by Hermes';
COMMENT ON COLUMN audit_messages.message_id         IS 'Solace message ID — globally unique, used for idempotency detection';
COMMENT ON COLUMN audit_messages.correlation_id     IS 'Business correlation identifier propagated from upstream system';
COMMENT ON COLUMN audit_messages.source_destination IS 'Solace source topic or queue name (e.g. flightschedules/>)';
COMMENT ON COLUMN audit_messages.consumer_group     IS 'Hermes Deployment name that processed this message';
COMMENT ON COLUMN audit_messages.message_payload    IS 'Full JSON payload, or S3 URI when claim-check threshold is exceeded';
COMMENT ON COLUMN audit_messages.payload_size_bytes IS 'Original payload size in bytes before any transformation';
COMMENT ON COLUMN audit_messages.payload_hash       IS 'SHA-256 hex digest of original payload for integrity verification';
COMMENT ON COLUMN audit_messages.sns_message_id     IS 'SNS publish confirmation ID — populated after successful outbox publish';
COMMENT ON COLUMN audit_messages.sns_topic_arn      IS 'Target SNS FIFO topic ARN';
COMMENT ON COLUMN audit_messages.status             IS 'Lifecycle state: RECEIVED | PROCESSING | PUBLISHED | FAILED | DLQ';
COMMENT ON COLUMN audit_messages.retry_count        IS 'Number of processing attempts (incremented on FAILED transitions)';
COMMENT ON COLUMN audit_messages.error_message      IS 'Last error detail string — populated on FAILED and DLQ transitions';
COMMENT ON COLUMN audit_messages.received_at        IS 'Timestamp when the Solace message was received by the FlowReceiver';
COMMENT ON COLUMN audit_messages.processed_at       IS 'Timestamp when processing completed (PUBLISHED or terminal failure)';
COMMENT ON COLUMN audit_messages.created_at         IS 'Row creation timestamp — immutable after insert';
COMMENT ON COLUMN audit_messages.updated_at         IS 'Last row modification timestamp — maintained by trigger';
