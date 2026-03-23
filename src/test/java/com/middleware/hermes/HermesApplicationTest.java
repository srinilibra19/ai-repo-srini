package com.middleware.hermes;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Spring context load test for HermesApplication.
 *
 * <p>Uses the {@code test} profile which:
 * <ul>
 *   <li>Replaces PostgreSQL with H2 in-memory (Flyway disabled)</li>
 *   <li>Excludes Solace auto-configuration so no broker connection is attempted</li>
 *   <li>Excludes AWS auto-configuration so no SDK client initialisation is attempted</li>
 * </ul>
 *
 * <p>This test verifies that the Spring context wires all beans correctly without
 * requiring any external infrastructure.
 */
@SpringBootTest
@ActiveProfiles("test")
class HermesApplicationTest {

    @Test
    void contextLoads() {
        // Verifies that the Spring application context starts without errors.
        // If any bean wiring fails, this test will fail with a detailed error.
    }
}
