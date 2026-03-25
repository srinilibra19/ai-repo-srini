package com.middleware.hermes.unit.model;

import com.middleware.hermes.model.OutboxStatus;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Unit tests for {@link OutboxStatus}.
 *
 * <p>Verifies that all expected enum constants exist with the correct names.
 * The string name of each constant is the value stored in the {@code status}
 * column of the {@code outbox_messages} table (VARCHAR). A rename or removal
 * of a constant would silently break DB status filtering — these tests catch that.
 */
class OutboxStatusTest {

    @Test
    void allFourConstantsExist() {
        assertThat(OutboxStatus.values())
                .containsExactlyInAnyOrder(
                        OutboxStatus.PENDING,
                        OutboxStatus.PUBLISHED,
                        OutboxStatus.FAILED,
                        OutboxStatus.DLQ);
    }

    @Test
    void exactlyFourConstantsDefined() {
        assertThat(OutboxStatus.values()).hasSize(4);
    }

    /**
     * Verifies that {@code OutboxStatus.valueOf(constant.name())} round-trips
     * correctly for every constant. This ensures the name stored in VARCHAR
     * columns can always be resolved back to the enum value.
     */
    @ParameterizedTest
    @EnumSource(OutboxStatus.class)
    void valueOfRoundTripsForAllConstants(OutboxStatus status) {
        assertThat(OutboxStatus.valueOf(status.name())).isEqualTo(status);
    }

    @Test
    void valueOfPending_returnsCorrectConstant() {
        assertThat(OutboxStatus.valueOf("PENDING")).isEqualTo(OutboxStatus.PENDING);
    }

    @Test
    void valueOfPublished_returnsCorrectConstant() {
        assertThat(OutboxStatus.valueOf("PUBLISHED")).isEqualTo(OutboxStatus.PUBLISHED);
    }

    @Test
    void valueOfFailed_returnsCorrectConstant() {
        assertThat(OutboxStatus.valueOf("FAILED")).isEqualTo(OutboxStatus.FAILED);
    }

    @Test
    void valueOfDlq_returnsCorrectConstant() {
        assertThat(OutboxStatus.valueOf("DLQ")).isEqualTo(OutboxStatus.DLQ);
    }

    @Test
    void valueOf_throwsIllegalArgumentExceptionForUnknownName() {
        assertThatThrownBy(() -> OutboxStatus.valueOf("UNKNOWN"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void valueOf_isCaseSensitive_rejectsLowercasePending() {
        assertThatThrownBy(() -> OutboxStatus.valueOf("pending"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
