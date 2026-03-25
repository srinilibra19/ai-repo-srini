package com.middleware.hermes.unit.repository;

import com.middleware.hermes.model.entity.AuditMessage;
import com.middleware.hermes.repository.AuditMessageRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.ActiveProfiles;

import java.time.OffsetDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Unit-level repository tests for {@link AuditMessageRepository}.
 *
 * <p>Uses H2 in PostgreSQL-compatibility mode (configured in application-test.yml)
 * with Hibernate {@code ddl-auto: create-drop} so that the entity schema is derived
 * from JPA annotations. Flyway is disabled for this test slice.
 *
 * <p>Full Flyway migration correctness (V1 migration SQL) is validated by the
 * Testcontainers integration tests in {@code integration/OutboxToSnsTest.java}.
 *
 * <p>Each test runs in its own rolled-back transaction (default for {@code @DataJpaTest})
 * to ensure full isolation between test methods.
 */
@DataJpaTest
@ActiveProfiles("test")
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class AuditMessageRepositoryTest {

    @Autowired
    private AuditMessageRepository repository;

    private static final String MSG_ID = "solace-msg-001";
    private static final String DESTINATION = "flightschedules/>";
    private static final String CONSUMER_GROUP = "hermes-flightschedules";

    @BeforeEach
    void setUp() {
        repository.deleteAll();
    }

    // -------------------------------------------------------------------------
    // Builder helper
    // -------------------------------------------------------------------------

    private AuditMessage buildMessage(String messageId) {
        return AuditMessage.builder()
                .messageId(messageId)
                .correlationId("corr-abc-123")
                .sourceDestination(DESTINATION)
                .consumerGroup(CONSUMER_GROUP)
                .payloadSizeBytes(512)
                .status("RECEIVED")
                .receivedAt(OffsetDateTime.now())
                .build();
    }

    // -------------------------------------------------------------------------
    // existsByMessageId
    // -------------------------------------------------------------------------

    @Test
    void existsByMessageId_returnsTrueWhenRecordExists() {
        repository.saveAndFlush(buildMessage(MSG_ID));

        assertThat(repository.existsByMessageId(MSG_ID)).isTrue();
    }

    @Test
    void existsByMessageId_returnsFalseWhenRecordDoesNotExist() {
        assertThat(repository.existsByMessageId("unknown-message-id")).isFalse();
    }

    // -------------------------------------------------------------------------
    // findByMessageId
    // -------------------------------------------------------------------------

    @Test
    void findByMessageId_returnsEntityWithAllFieldsPopulated() {
        repository.saveAndFlush(buildMessage(MSG_ID));

        Optional<AuditMessage> result = repository.findByMessageId(MSG_ID);

        assertThat(result).isPresent();
        AuditMessage found = result.get();
        assertThat(found.getMessageId()).isEqualTo(MSG_ID);
        assertThat(found.getCorrelationId()).isEqualTo("corr-abc-123");
        assertThat(found.getSourceDestination()).isEqualTo(DESTINATION);
        assertThat(found.getConsumerGroup()).isEqualTo(CONSUMER_GROUP);
        assertThat(found.getStatus()).isEqualTo("RECEIVED");
        assertThat(found.getRetryCount()).isEqualTo(0);
        assertThat(found.getPayloadSizeBytes()).isEqualTo(512);
        assertThat(found.getId()).isNotNull();
    }

    @Test
    void findByMessageId_returnsEmptyOptionalWhenRecordDoesNotExist() {
        Optional<AuditMessage> result = repository.findByMessageId("nonexistent-id");

        assertThat(result).isEmpty();
    }

    // -------------------------------------------------------------------------
    // updateStatusByMessageId
    // -------------------------------------------------------------------------

    @Test
    void updateStatusByMessageId_updatesStatusFromReceivedToProcessing() {
        repository.saveAndFlush(buildMessage(MSG_ID));

        repository.updateStatusByMessageId(MSG_ID, "PROCESSING");

        AuditMessage updated = repository.findByMessageId(MSG_ID).orElseThrow();
        assertThat(updated.getStatus()).isEqualTo("PROCESSING");
    }

    @Test
    void updateStatusByMessageId_updatesStatusFromReceivedToPublished() {
        repository.saveAndFlush(buildMessage(MSG_ID));

        repository.updateStatusByMessageId(MSG_ID, "PUBLISHED");

        AuditMessage updated = repository.findByMessageId(MSG_ID).orElseThrow();
        assertThat(updated.getStatus()).isEqualTo("PUBLISHED");
    }

    @Test
    void updateStatusByMessageId_doesNotAffectOtherRecords() {
        repository.saveAndFlush(buildMessage(MSG_ID));
        repository.saveAndFlush(buildMessage("other-msg-999"));

        repository.updateStatusByMessageId(MSG_ID, "FAILED");

        AuditMessage untouched = repository.findByMessageId("other-msg-999").orElseThrow();
        assertThat(untouched.getStatus()).isEqualTo("RECEIVED");
    }

    // -------------------------------------------------------------------------
    // Idempotency — UNIQUE constraint on message_id
    // -------------------------------------------------------------------------

    @Test
    void save_throwsDataIntegrityViolationOnDuplicateMessageId() {
        repository.saveAndFlush(buildMessage(MSG_ID));

        AuditMessage duplicate = buildMessage(MSG_ID);

        assertThatThrownBy(() -> repository.saveAndFlush(duplicate))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    // -------------------------------------------------------------------------
    // Default values
    // -------------------------------------------------------------------------

    @Test
    void save_setsRetryCountDefaultToZero() {
        AuditMessage saved = repository.saveAndFlush(
                AuditMessage.builder()
                        .messageId("msg-defaults")
                        .sourceDestination(DESTINATION)
                        .consumerGroup(CONSUMER_GROUP)
                        .payloadSizeBytes(128)
                        .status("RECEIVED")
                        .receivedAt(OffsetDateTime.now())
                        .build());

        assertThat(saved.getRetryCount()).isEqualTo(0);
    }

    @Test
    void save_allowsNullableFieldsToBeNull() {
        AuditMessage saved = repository.saveAndFlush(
                AuditMessage.builder()
                        .messageId("msg-nullables")
                        .sourceDestination(DESTINATION)
                        .consumerGroup(CONSUMER_GROUP)
                        .payloadSizeBytes(64)
                        .status("RECEIVED")
                        .receivedAt(OffsetDateTime.now())
                        .build());

        assertThat(saved.getCorrelationId()).isNull();
        assertThat(saved.getMessagePayload()).isNull();
        assertThat(saved.getPayloadHash()).isNull();
        assertThat(saved.getSnsMessageId()).isNull();
        assertThat(saved.getSnsTopicArn()).isNull();
        assertThat(saved.getProcessedAt()).isNull();
        assertThat(saved.getErrorMessage()).isNull();
    }
}
