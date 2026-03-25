package com.middleware.hermes.repository;

import com.middleware.hermes.model.entity.AuditMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

/**
 * Spring Data JPA repository for {@link AuditMessage}.
 *
 * <p>All write operations that touch this repository must be called from within
 * a {@code @Transactional} boundary declared on the calling service method
 * (never directly from a controller or listener thread without a transaction).
 *
 * <p>The idempotency lookup ({@link #existsByMessageId}) is the hot-path query
 * executed before every message is processed. It is backed by the unique index
 * {@code idx_audit_messages_message_id} (created in V1 migration).
 */
public interface AuditMessageRepository extends JpaRepository<AuditMessage, Long> {

    /**
     * Idempotency check — returns {@code true} if a record with the given
     * {@code messageId} already exists in the audit table.
     *
     * <p>Backed by the unique index on {@code message_id}. This is the primary
     * duplicate-detection gate called by {@code IdempotencyChecker} before
     * starting any processing transaction.
     *
     * @param messageId the Solace message ID to check
     * @return {@code true} if a record already exists; {@code false} otherwise
     */
    boolean existsByMessageId(String messageId);

    /**
     * Fetch a single audit record by its Solace message ID.
     *
     * <p>Used after a {@link org.springframework.dao.DataIntegrityViolationException}
     * on a concurrent duplicate insert — lets the caller confirm the duplicate
     * and retrieve the existing record's ID for correlation logging.
     *
     * @param messageId the Solace message ID
     * @return the existing {@link AuditMessage}, or empty if not found
     */
    Optional<AuditMessage> findByMessageId(String messageId);

    /**
     * Update the status of an existing audit record.
     *
     * <p>Used by the processing pipeline to transition status without reloading
     * the full entity (avoids a SELECT on the hot path).
     * Must be called within an active {@code @Transactional} boundary.
     *
     * @param messageId the Solace message ID identifying the record to update
     * @param status    the new status value (e.g. {@code "PROCESSING"}, {@code "PUBLISHED"})
     */
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query("""
            UPDATE AuditMessage a
               SET a.status = :status
             WHERE a.messageId = :messageId
            """)
    void updateStatusByMessageId(@Param("messageId") String messageId,
                                 @Param("status") String status);
}
