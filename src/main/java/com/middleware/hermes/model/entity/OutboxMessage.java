package com.middleware.hermes.model.entity;

import com.middleware.hermes.model.OutboxStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.ColumnDefault;
import org.hibernate.annotations.Generated;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.generator.EventType;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

/**
 * JPA entity representing a row in the {@code outbox_messages} table.
 *
 * <p>Each row represents one message that must be published to SNS FIFO.
 * The outbox poller reads {@link OutboxStatus#PENDING} rows using
 * {@code SELECT ... FOR UPDATE SKIP LOCKED} and publishes them to SNS FIFO.
 *
 * <p>Status transitions:
 * <pre>
 *   PENDING → PUBLISHED  (outbox poller published successfully)
 *   PENDING → FAILED     (publish attempt failed — retry eligible)
 *   FAILED  → PUBLISHED  (retry succeeded)
 *   FAILED  → DLQ        (retry count exhausted — terminal)
 * </pre>
 *
 * <p>The {@code deduplication_id} carries a UNIQUE constraint. It must be set
 * to the originating Solace message ID so that SNS FIFO deduplication is stable
 * across retries (a new UUID on each retry would break SNS deduplication).
 *
 * <p>Both the audit record and this outbox record are written in a single
 * {@code @Transactional} method — they commit or rollback together (REQ-DB-008).
 */
@Entity
@Table(name = "outbox_messages")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OutboxMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false, updatable = false)
    private Long id;

    /**
     * Business correlation identifier — typically the Solace {@code correlationId}.
     * Propagated to SNS message attributes for end-to-end tracing.
     */
    @Column(name = "aggregate_id", length = 255)
    private String aggregateId;

    /**
     * Event classification for downstream routing
     * (e.g. {@code FlightScheduleUpdated}, {@code FlightScheduleCancelled}).
     */
    @Column(name = "event_type", length = 100)
    private String eventType;

    /**
     * SNS message payload — canonical JSON or a {@code ClaimCheckReference} JSON
     * when the original payload exceeds the 200 KB claim-check threshold.
     * Stored as JSONB in PostgreSQL.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload", columnDefinition = "jsonb")
    private String payload;

    /** Solace destination this message originated from (e.g. {@code flightschedules/>}). */
    @Column(name = "destination_name", nullable = false, length = 512)
    private String destinationName;

    /** Target SNS FIFO topic ARN for this outbox record. */
    @Column(name = "target_sns_arn", nullable = false, length = 512)
    private String targetSnsArn;

    /**
     * SNS FIFO {@code MessageGroupId} — controls message ordering within the topic.
     * Typically set to the destination name (e.g. {@code "flightschedules"}).
     */
    @Column(name = "message_group_id", nullable = false, length = 128)
    private String messageGroupId;

    /**
     * SNS FIFO {@code MessageDeduplicationId} — must be the originating Solace
     * message ID (not a random UUID) to ensure stable deduplication across retries.
     * Carries a UNIQUE constraint in the DB.
     */
    @Column(name = "deduplication_id", nullable = false, unique = true, length = 128)
    private String deduplicationId;

    /**
     * Outbox lifecycle status.
     * Stored as {@code VARCHAR(20)} matching the V2 migration column definition.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    @Builder.Default
    private OutboxStatus status = OutboxStatus.PENDING;

    /** Number of SNS publish attempts. Incremented on each FAILED transition. */
    @Column(name = "retry_count", nullable = false)
    @Builder.Default
    private Integer retryCount = 0;

    /** Last SNS publish error detail — populated on FAILED and DLQ transitions. */
    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    /**
     * Row creation timestamp — owned by the database (DEFAULT NOW()).
     * {@code @Generated(INSERT)} tells Hibernate to omit this column from the
     * INSERT statement (allowing the DB DEFAULT to fire) and re-fetch the
     * value after insert. Immutable after creation ({@code updatable = false}).
     */
    @ColumnDefault("now()")
    @Generated(event = EventType.INSERT)
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    /** When the row was successfully published to SNS FIFO. Null until published. */
    @Column(name = "published_at")
    private OffsetDateTime publishedAt;
}
