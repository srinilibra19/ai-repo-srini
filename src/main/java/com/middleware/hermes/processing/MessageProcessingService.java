package com.middleware.hermes.processing;

import com.solacesystems.jcsmp.BytesXMLMessage;

/**
 * Service contract for processing a single Solace message end-to-end.
 *
 * <p>Implementations (see {@code MessageProcessor} in E6-004) must complete
 * the full audit + outbox write within a single {@code @Transactional} boundary
 * before returning. The caller ({@link com.middleware.hermes.messaging.SolaceMessageConsumer})
 * ACKs the JCSMP message after this method returns successfully — never before.
 *
 * <p>If this method throws any exception, the caller will NOT ack the message.
 * The message will be redelivered by the Solace broker within the configured
 * prefetch window.
 */
public interface MessageProcessingService {

    /**
     * Process a single Solace message.
     *
     * <p>The caller ACKs the message only after this method returns without
     * exception. Implementations must NOT call {@code message.ackMessage()} —
     * that responsibility belongs exclusively to the caller.
     *
     * @param message the raw JCSMP message received from the broker.
     *                Treat all content as untrusted input — validate before use.
     * @throws com.middleware.hermes.exception.MessageValidationException
     *                 if the payload fails schema validation
     * @throws com.middleware.hermes.exception.DuplicateMessageException
     *                 if the message ID has already been successfully processed
     */
    void processMessage(BytesXMLMessage message);
}
