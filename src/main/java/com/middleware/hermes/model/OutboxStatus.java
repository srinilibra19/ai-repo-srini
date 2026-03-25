package com.middleware.hermes.model;

/**
 * Lifecycle status values for the {@code outbox_messages} table.
 *
 * <p>Valid transitions:
 * <pre>
 *   PENDING → PUBLISHED  (outbox poller published successfully to SNS FIFO)
 *   PENDING → FAILED     (publish attempt failed — retry eligible)
 *   FAILED  → PUBLISHED  (retry succeeded)
 *   FAILED  → DLQ        (retry count exhausted — terminal state)
 * </pre>
 *
 * <p>Stored as {@code VARCHAR(20)} in PostgreSQL (see migration V2).
 * The string value written to the database is the enum name (e.g. {@code "PENDING"}).
 *
 * <p>Note: {@code audit_messages.status} uses a distinct set of values
 * ({@code RECEIVED}, {@code PROCESSING}, {@code PUBLISHED}, {@code FAILED}, {@code DLQ})
 * and is stored as a plain {@code String} on {@link com.middleware.hermes.model.entity.AuditMessage}
 * because the audit lifecycle includes intermediate states not present in the outbox lifecycle.
 */
public enum OutboxStatus {

    /**
     * Initial state — outbox record created, not yet picked up by the poller.
     * The outbox poller queries for all rows in this state using
     * {@code SELECT ... FOR UPDATE SKIP LOCKED}.
     */
    PENDING,

    /**
     * Terminal success state — message was published to SNS FIFO and the
     * outbox row updated with {@code published_at = NOW()}.
     */
    PUBLISHED,

    /**
     * Transient failure state — at least one publish attempt failed.
     * The poller will retry until the configured maximum retry count is reached,
     * at which point the record transitions to {@link #DLQ}.
     */
    FAILED,

    /**
     * Terminal failure state — maximum retries exhausted.
     * The record is no longer eligible for automatic retry.
     * A CloudWatch alarm must fire when rows enter this state.
     */
    DLQ
}
