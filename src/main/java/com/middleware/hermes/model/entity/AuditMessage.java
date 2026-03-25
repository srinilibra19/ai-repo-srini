package com.middleware.hermes.model.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
 * JPA entity representing a row in the {@code audit_messages} table.
 *
 * <p>Records the full lifecycle of every Solace message received by Hermes,
 * from initial receipt through SNS publication (or terminal failure).
 *
 * <p>Status transitions:
 * <pre>
 *   RECEIVED → PROCESSING → PUBLISHED
 *                         → FAILED → DLQ
 * </pre>
 *
 * <p>The {@code message_id} column carries a UNIQUE constraint enforced at both
 * the database level (migration V1) and application level (IdempotencyChecker).
 */
@Entity
@Table(name = "audit_messages")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AuditMessage {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false, updatable = false)
    private Long id;

    /**
     * Solace message ID — globally unique, used for idempotency detection.
     * Carries a UNIQUE constraint in the DB; an insert of a duplicate value
     * raises {@code DataIntegrityViolationException}.
     */
    @Column(name = "message_id", nullable = false, unique = true, length = 255, updatable = false)
    private String messageId;

    /** Business correlation identifier propagated from the upstream system. */
    @Column(name = "correlation_id", length = 255)
    private String correlationId;

    /** Solace source topic or queue name (e.g. {@code flightschedules/>}). */
    @Column(name = "source_destination", nullable = false, length = 512)
    private String sourceDestination;

    /** Hermes Deployment name that processed this message. */
    @Column(name = "consumer_group", nullable = false, length = 255)
    private String consumerGroup;

    /**
     * Full JSON payload, or S3 URI when the claim-check threshold (200 KB) is exceeded.
     * Stored as JSONB in PostgreSQL for indexed querying.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "message_payload", columnDefinition = "jsonb")
    private String messagePayload;

    /** Original payload size in bytes before any transformation. */
    @Column(name = "payload_size_bytes", nullable = false)
    private Integer payloadSizeBytes;

    /** SHA-256 hex digest of the original payload for integrity verification. */
    @Column(name = "payload_hash", length = 64)
    private String payloadHash;

    /** SNS publish confirmation ID — populated after successful outbox publish. */
    @Column(name = "sns_message_id", length = 255)
    private String snsMessageId;

    /** Target SNS FIFO topic ARN. */
    @Column(name = "sns_topic_arn", length = 512)
    private String snsTopicArn;

    /**
     * Message lifecycle status.
     * Valid values: {@code RECEIVED}, {@code PROCESSING}, {@code PUBLISHED},
     * {@code FAILED}, {@code DLQ}.
     * Stored as VARCHAR(50) — matches the V1 migration column definition.
     */
    @Column(name = "status", nullable = false, length = 50)
    private String status;

    /** Number of processing attempts. Incremented on each FAILED transition. */
    @Column(name = "retry_count", nullable = false)
    @Builder.Default
    private Integer retryCount = 0;

    /** Last error detail string — populated on FAILED and DLQ transitions. */
    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    /** When the Solace message was received by the FlowReceiver. */
    @Column(name = "received_at", nullable = false)
    private OffsetDateTime receivedAt;

    /** When processing completed (PUBLISHED or terminal failure). */
    @Column(name = "processed_at")
    private OffsetDateTime processedAt;

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

    /**
     * Last row modification timestamp — owned by the database.
     * Set to NOW() by DEFAULT on INSERT; overwritten by the DB trigger
     * {@code update_audit_messages_updated_at} on every UPDATE.
     * {@code @Generated(INSERT, UPDATE)} tells Hibernate to re-fetch this
     * value after every write so the Java object stays in sync with the DB.
     */
    @ColumnDefault("now()")
    @Generated(event = {EventType.INSERT, EventType.UPDATE})
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;
}
