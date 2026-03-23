package com.middleware.hermes;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Hermes — Solace-to-AWS messaging bridge.
 *
 * <p>{@code @EnableScheduling} activates the outbox poller's {@code @Scheduled} fallback poll.
 * The primary trigger is PostgreSQL LISTEN/NOTIFY; the 500ms fallback ensures no records are
 * stuck if a NOTIFY is missed.
 */
@SpringBootApplication
@EnableScheduling
public class HermesApplication {

    public static void main(final String[] args) {
        SpringApplication.run(HermesApplication.class, args);
    }
}
