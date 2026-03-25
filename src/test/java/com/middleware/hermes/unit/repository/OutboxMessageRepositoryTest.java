package com.middleware.hermes.unit.repository;

import com.middleware.hermes.model.OutboxStatus;
import com.middleware.hermes.model.entity.OutboxMessage;
import com.middleware.hermes.repository.OutboxMessageRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.ActiveProfiles;

import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Unit tests for {@link OutboxMessageRepository} and {@link OutboxMessage} entity behaviour.
 *
 * <p>Uses {@code @DataJpaTest} with H2 in PostgreSQL-compatibility mode.
 * Flyway is disabled; Hibernate {@code create-drop} DDL satisfies the schema.
 *
 * <p>Note: the NOTIFY trigger ({@code fn_outbox_notify}) is a PostgreSQL-only construct
 * and is NOT exercised here — it requires a real PostgreSQL instance. Trigger behaviour
 * is verified in the Testcontainers integration test suite (US-E11-002).
 */
@DataJpaTest
@ActiveProfiles("test")
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class OutboxMessageRepositoryTest {

    @Autowired
    private OutboxMessageRepository repository;

    private OutboxMessage baseMessage;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
        baseMessage = OutboxMessage.builder()
                .aggregateId("corr-001")
                .eventType("FlightScheduleUpdated")
                .payload("{\"flightNumber\":\"AA100\"}")
                .destinationName("flightschedules/>")
                .targetSnsArn("arn:aws:sns:us-east-1:000000000000:hermes-flightschedules.fifo")
                .messageGroupId("flightschedules")
                .deduplicationId("solace-msg-001")
                .build();
    }

    // -------------------------------------------------------------------------
    // Happy path — save and retrieve
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("save: persists outbox message with default status PENDING and retryCount 0")
    void save_persistsWithDefaults() {
        OutboxMessage saved = repository.save(baseMessage);

        assertThat(saved.getId()).isNotNull();
        assertThat(saved.getStatus()).isEqualTo(OutboxStatus.PENDING);
        assertThat(saved.getRetryCount()).isZero();
        assertThat(saved.getPublishedAt()).isNull();
        assertThat(saved.getErrorMessage()).isNull();
    }

    @Test
    @DisplayName("save: createdAt is populated by the database after insert")
    void save_createdAtPopulatedByDb() {
        OutboxMessage saved = repository.save(baseMessage);
        // @Generated(INSERT) re-fetches from DB — must not be null
        assertThat(saved.getCreatedAt()).isNotNull();
    }

    @Test
    @DisplayName("save: OutboxStatus enum persisted and retrieved as string value")
    void save_enumRoundTrip() {
        OutboxMessage saved = repository.save(baseMessage);
        OutboxMessage found = repository.findById(saved.getId()).orElseThrow();
        assertThat(found.getStatus()).isEqualTo(OutboxStatus.PENDING);
    }

    // -------------------------------------------------------------------------
    // Unique constraint on deduplication_id
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("save: duplicate deduplicationId raises DataIntegrityViolationException")
    void save_duplicateDeduplicationId_throws() {
        repository.save(baseMessage);

        OutboxMessage duplicate = OutboxMessage.builder()
                .aggregateId("corr-002")
                .eventType("FlightScheduleUpdated")
                .payload("{\"flightNumber\":\"AA200\"}")
                .destinationName("flightschedules/>")
                .targetSnsArn("arn:aws:sns:us-east-1:000000000000:hermes-flightschedules.fifo")
                .messageGroupId("flightschedules")
                .deduplicationId("solace-msg-001")   // same deduplicationId
                .build();

        assertThatThrownBy(() -> {
            repository.save(duplicate);
            repository.flush();
        }).isInstanceOf(DataIntegrityViolationException.class);
    }

    // -------------------------------------------------------------------------
    // markPublished
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("markPublished: transitions status to PUBLISHED and sets publishedAt")
    void markPublished_updatesStatusAndTimestamp() {
        OutboxMessage saved = repository.save(baseMessage);
        OffsetDateTime publishedAt = OffsetDateTime.now();

        repository.markPublished(saved.getId(), publishedAt);

        OutboxMessage updated = repository.findById(saved.getId()).orElseThrow();
        assertThat(updated.getStatus()).isEqualTo(OutboxStatus.PUBLISHED);
        assertThat(updated.getPublishedAt()).isNotNull();
    }

    // -------------------------------------------------------------------------
    // markFailed
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("markFailed: transitions status to FAILED and increments retryCount")
    void markFailed_incrementsRetryCount() {
        OutboxMessage saved = repository.save(baseMessage);
        assertThat(saved.getRetryCount()).isZero();

        repository.markFailed(saved.getId(), "SNS throttled");
        repository.markFailed(saved.getId(), "SNS throttled again");

        OutboxMessage updated = repository.findById(saved.getId()).orElseThrow();
        assertThat(updated.getStatus()).isEqualTo(OutboxStatus.FAILED);
        assertThat(updated.getRetryCount()).isEqualTo(2);
        assertThat(updated.getErrorMessage()).isEqualTo("SNS throttled again");
    }

    // -------------------------------------------------------------------------
    // markDlq
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("markDlq: transitions status to DLQ and records error message")
    void markDlq_setsTerminalState() {
        OutboxMessage saved = repository.save(baseMessage);

        repository.markDlq(saved.getId(), "Max retries exhausted after 3 attempts");

        OutboxMessage updated = repository.findById(saved.getId()).orElseThrow();
        assertThat(updated.getStatus()).isEqualTo(OutboxStatus.DLQ);
        assertThat(updated.getErrorMessage()).isEqualTo("Max retries exhausted after 3 attempts");
    }

    // -------------------------------------------------------------------------
    // countByStatus
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("countByStatus: returns correct count for PENDING rows")
    void countByStatus_pendingRows() {
        repository.save(baseMessage);
        repository.save(OutboxMessage.builder()
                .destinationName("flightschedules/>")
                .targetSnsArn("arn:aws:sns:us-east-1:000000000000:hermes-flightschedules.fifo")
                .messageGroupId("flightschedules")
                .deduplicationId("solace-msg-002")
                .build());

        assertThat(repository.countByStatus(OutboxStatus.PENDING)).isEqualTo(2);
        assertThat(repository.countByStatus(OutboxStatus.PUBLISHED)).isZero();
    }

    @Test
    @DisplayName("countByStatus: returns 0 when no rows match the given status")
    void countByStatus_noMatch_returnsZero() {
        repository.save(baseMessage);
        assertThat(repository.countByStatus(OutboxStatus.DLQ)).isZero();
    }

    // -------------------------------------------------------------------------
    // Status transition sequence
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("status transitions: PENDING -> FAILED -> DLQ follows valid lifecycle")
    void statusTransition_pendingToFailedToDlq() {
        OutboxMessage saved = repository.save(baseMessage);
        assertThat(saved.getStatus()).isEqualTo(OutboxStatus.PENDING);

        repository.markFailed(saved.getId(), "First failure");
        assertThat(repository.findById(saved.getId()).orElseThrow().getStatus())
                .isEqualTo(OutboxStatus.FAILED);

        repository.markDlq(saved.getId(), "Retry limit reached");
        assertThat(repository.findById(saved.getId()).orElseThrow().getStatus())
                .isEqualTo(OutboxStatus.DLQ);
    }
}
