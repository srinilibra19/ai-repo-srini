package com.middleware.hermes.repository;

import com.middleware.hermes.model.OutboxStatus;
import com.middleware.hermes.model.entity.OutboxMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Spring Data JPA repository for {@link OutboxMessage}.
 *
 * <p>The two most critical methods here are:
 * <ul>
 *   <li>{@link #findPendingForUpdate(int)} — used by the outbox poller; must use
 *       {@code FOR UPDATE SKIP LOCKED} to allow multiple pods to compete safely.</li>
 *   <li>{@link #markPublished(Long, String, OffsetDateTime)} — bulk-update after
 *       successful SNS publish; must clear the first-level cache to avoid stale reads.</li>
 * </ul>
 *
 * <p>All write methods must be called from within a {@code @Transactional} boundary
 * declared on the calling service method.
 */
public interface OutboxMessageRepository extends JpaRepository<OutboxMessage, Long> {

    /**
     * Fetch up to {@code limit} PENDING outbox rows and lock them for update,
     * skipping any rows already locked by another transaction (concurrent pod).
     *
     * <p>This is the primary poller query (REQ-DB-015). The {@code SKIP LOCKED}
     * hint prevents competing poller threads/pods from blocking each other.
     * Must be called within an active {@code @Transactional} boundary.
     *
     * @param limit maximum number of rows to fetch per poll cycle
     * @return locked PENDING outbox rows, ordered by {@code created_at} ascending
     */
    @Transactional
    @Query(value = """
            SELECT * FROM outbox_messages
             WHERE status = 'PENDING'
             ORDER BY created_at
             LIMIT :limit
             FOR UPDATE SKIP LOCKED
            """,
            nativeQuery = true)
    List<OutboxMessage> findPendingForUpdate(@Param("limit") int limit);

    /**
     * Also fetch FAILED rows eligible for retry (retry_count below the configured max).
     * Called by the fallback poll sweep to catch messages that failed in a previous cycle.
     *
     * @param maxRetries rows with {@code retry_count} strictly less than this value are eligible
     * @param limit      maximum number of rows to fetch
     * @return locked FAILED outbox rows eligible for retry, ordered by {@code created_at}
     */
    @Transactional
    @Query(value = """
            SELECT * FROM outbox_messages
             WHERE status = 'FAILED'
               AND retry_count < :maxRetries
             ORDER BY created_at
             LIMIT :limit
             FOR UPDATE SKIP LOCKED
            """,
            nativeQuery = true)
    List<OutboxMessage> findFailedForRetry(@Param("maxRetries") int maxRetries,
                                           @Param("limit") int limit);

    /**
     * Transition a single outbox row to {@link OutboxStatus#PUBLISHED} after a
     * successful SNS publish.
     *
     * <p>{@code clearAutomatically = true} evicts the updated row from the
     * first-level cache so subsequent reads within the same session see the
     * updated status — prevents stale-read bugs in the poller transaction.
     *
     * @param id          primary key of the outbox row
     * @param publishedAt  timestamp of the successful publish
     */
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query("""
            UPDATE OutboxMessage o
               SET o.status = com.middleware.hermes.model.OutboxStatus.PUBLISHED,
                   o.publishedAt = :publishedAt
             WHERE o.id = :id
            """)
    void markPublished(@Param("id") Long id,
                       @Param("publishedAt") OffsetDateTime publishedAt);

    /**
     * Increment the retry count and record the error on a FAILED publish attempt.
     * Transitions status to {@link OutboxStatus#FAILED}.
     *
     * @param id           primary key of the outbox row
     * @param errorMessage last error detail string from the SNS publish exception
     */
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query("""
            UPDATE OutboxMessage o
               SET o.status = com.middleware.hermes.model.OutboxStatus.FAILED,
                   o.retryCount = o.retryCount + 1,
                   o.errorMessage = :errorMessage
             WHERE o.id = :id
            """)
    void markFailed(@Param("id") Long id,
                    @Param("errorMessage") String errorMessage);

    /**
     * Transition a row to {@link OutboxStatus#DLQ} after retry exhaustion.
     * This is a terminal state — the row will not be picked up by the poller again.
     *
     * @param id           primary key of the outbox row
     * @param errorMessage final error detail explaining why DLQ was reached
     */
    @Modifying(clearAutomatically = true)
    @Transactional
    @Query("""
            UPDATE OutboxMessage o
               SET o.status = com.middleware.hermes.model.OutboxStatus.DLQ,
                   o.errorMessage = :errorMessage
             WHERE o.id = :id
            """)
    void markDlq(@Param("id") Long id,
                 @Param("errorMessage") String errorMessage);

    /**
     * Count of rows in {@link OutboxStatus#PENDING} status — published every 30 s
     * as the {@code outbox.pending.count} Micrometer gauge (REQ-OBS-006).
     *
     * @return number of rows with status PENDING
     */
    @Transactional(readOnly = true)
    long countByStatus(OutboxStatus status);
}
