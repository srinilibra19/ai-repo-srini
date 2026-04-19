package com.middleware.hermes.messaging;

import com.middleware.hermes.processing.MessageProcessingService;
import com.solacesystems.jcsmp.BytesXMLMessage;
import com.solacesystems.jcsmp.ConsumerFlowProperties;
import com.solacesystems.jcsmp.EndpointProperties;
import com.solacesystems.jcsmp.FlowEventArgs;
import com.solacesystems.jcsmp.FlowEventHandler;
import com.solacesystems.jcsmp.FlowReceiver;
import com.solacesystems.jcsmp.JCSMPException;
import com.solacesystems.jcsmp.JCSMPSession;
import com.solacesystems.jcsmp.Queue;
import com.solacesystems.jcsmp.XMLMessageListener;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Binds a JCSMP {@link FlowReceiver} to the {@code hermes.flightschedules} queue
 * and dispatches each message to {@link MessageProcessingService} on a dedicated
 * Solace bulkhead thread pool.
 *
 * <p><b>ACK contract</b>: a message is acknowledged <em>only</em> after
 * {@link MessageProcessingService#processMessage} returns without exception —
 * i.e., only after the audit + outbox DB transaction has committed.
 * Any exception leaves the message unacknowledged so the Solace broker will
 * redeliver it within the configured prefetch window.
 *
 * <p><b>Backpressure</b>: when the {@code rdsWrite} circuit breaker opens
 * (RDS unavailable), the FlowReceiver is stopped immediately. Messages remain
 * on the Solace broker queue — they are never silently dropped. The FlowReceiver
 * restarts when the circuit breaker transitions to CLOSED or HALF_OPEN.
 *
 * <p><b>Graceful shutdown</b>: on SIGTERM, Spring calls {@link #stop()}.
 * The FlowReceiver is stopped first (no new messages accepted), then the
 * processing executor is drained (up to {@code hermes.solace.stop-timeout-millis})
 * so all in-flight DB writes complete before the connection pool closes.
 *
 * <p><b>Thread pool</b>: one {@link ThreadPoolExecutor} (the Solace bulkhead)
 * is created per consumer instance. RDS writes and SNS publishes use separate
 * thread pools defined in {@code ResilienceConfig} (E6-001).
 */
@Slf4j
@Component
public class SolaceMessageConsumer implements SmartLifecycle {

    private static final String RDS_CIRCUIT_BREAKER_NAME = "rdsWrite";

    private final JCSMPSession session;
    private final Queue queue;
    private final EndpointProperties endpointProperties;
    private final MessageProcessingService processingService;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final String destination;
    private final int processingThreadPoolSize;
    private final long stopTimeoutMillis;

    private volatile FlowReceiver flowReceiver;
    private volatile ThreadPoolExecutor processingExecutor;
    private final AtomicBoolean running = new AtomicBoolean(false);

    public SolaceMessageConsumer(
            JCSMPSession session,
            Queue queue,
            EndpointProperties endpointProperties,
            MessageProcessingService processingService,
            CircuitBreakerRegistry circuitBreakerRegistry,
            @Value("${hermes.solace.destination:flightschedules}") String destination,
            @Value("${hermes.solace.processing-thread-pool-size:16}") int processingThreadPoolSize,
            @Value("${hermes.solace.stop-timeout-millis:45000}") long stopTimeoutMillis) {
        this.session = session;
        this.queue = queue;
        this.endpointProperties = endpointProperties;
        this.processingService = processingService;
        this.circuitBreakerRegistry = circuitBreakerRegistry;
        this.destination = destination;
        this.processingThreadPoolSize = processingThreadPoolSize;
        this.stopTimeoutMillis = stopTimeoutMillis;
    }

    // -------------------------------------------------------------------------
    // SmartLifecycle — startup
    // -------------------------------------------------------------------------

    /**
     * Starts the FlowReceiver and registers RDS circuit-breaker backpressure callbacks.
     * Called by Spring after all lower-phase beans (repositories, DB pool) are ready.
     */
    @Override
    public void start() {
        if (running.get()) {
            log.warn("SolaceMessageConsumer.start() called but already running: destination={}", destination);
            return;
        }

        processingExecutor = new ThreadPoolExecutor(
                processingThreadPoolSize,
                processingThreadPoolSize,
                0L, TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(processingThreadPoolSize * 2),
                r -> {
                    final Thread t = new Thread(r);
                    t.setName("solace-proc-" + destination + "-" + t.getId());
                    t.setDaemon(false);
                    return t;
                },
                // CallerRunsPolicy: when queue is full, the JCSMP receiver thread runs
                // the task directly — naturally blocking new message receipt (backpressure)
                new ThreadPoolExecutor.CallerRunsPolicy());

        try {
            final ConsumerFlowProperties flowProps = new ConsumerFlowProperties();
            flowProps.setEndpoint(queue);
            flowProps.setEndpointProperties(endpointProperties);

            flowReceiver = session.createFlow(
                    new SolaceXmlMessageListener(),
                    flowProps,
                    endpointProperties,
                    new SolaceFlowEventHandler());

            registerCircuitBreakerCallbacks();
            flowReceiver.start();
            running.set(true);

            log.info("FlowReceiver started: destination={} queue={} threadPoolSize={}",
                    destination, queue.getName(), processingThreadPoolSize);

        } catch (JCSMPException e) {
            log.error("Failed to start FlowReceiver: destination={} error={}",
                    destination, e.getMessage(), e);
            throw new IllegalStateException(
                    "FlowReceiver failed to start for destination: " + destination, e);
        }
    }

    // -------------------------------------------------------------------------
    // SmartLifecycle — shutdown
    // -------------------------------------------------------------------------

    /**
     * Stops the FlowReceiver (backpressure), drains the processing executor,
     * then closes the JCSMP session. Called by Spring on SIGTERM.
     *
     * <p>Waits up to {@code hermes.solace.stop-timeout-millis} (default 45 s)
     * for in-flight messages to finish processing. This fits within the
     * {@code spring.lifecycle.timeout-per-shutdown-phase: 55s} window defined
     * in {@code application.yml}, which in turn fits within the Helm
     * {@code terminationGracePeriodSeconds: 60}.
     */
    @Override
    public void stop() {
        if (!running.compareAndSet(true, false)) {
            return;
        }
        log.info("Stopping SolaceMessageConsumer: destination={}", destination);

        if (flowReceiver != null) {
            flowReceiver.stop();
            log.info("FlowReceiver stopped (no new messages accepted): destination={}", destination);
        }

        if (processingExecutor != null) {
            processingExecutor.shutdown();
            try {
                if (!processingExecutor.awaitTermination(stopTimeoutMillis, TimeUnit.MILLISECONDS)) {
                    log.warn("Processing executor did not drain within timeout — forcing shutdown: "
                                    + "destination={} timeoutMs={}",
                            destination, stopTimeoutMillis);
                    processingExecutor.shutdownNow();
                }
            } catch (InterruptedException e) {
                log.warn("Interrupted while awaiting executor drain: destination={}", destination, e);
                processingExecutor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }

        try {
            session.closeSession();
            log.info("JCSMP session closed: destination={}", destination);
        } catch (Exception e) {
            log.warn("Error closing JCSMP session during shutdown: destination={} error={}",
                    destination, e.getMessage(), e);
        }

        log.info("SolaceMessageConsumer stopped: destination={}", destination);
    }

    @Override
    public boolean isRunning() {
        return running.get();
    }

    /**
     * Phase {@link SmartLifecycle#DEFAULT_PHASE} ({@code Integer.MAX_VALUE}):
     * starts last (after DB pool and repositories are ready),
     * stops first (before DB pool closes, giving the executor time to drain).
     */
    @Override
    public int getPhase() {
        return DEFAULT_PHASE;
    }

    // -------------------------------------------------------------------------
    // Circuit-breaker backpressure
    // -------------------------------------------------------------------------

    private void registerCircuitBreakerCallbacks() {
        final CircuitBreaker cb = circuitBreakerRegistry.circuitBreaker(RDS_CIRCUIT_BREAKER_NAME);
        cb.getEventPublisher().onStateTransition(event -> {
            final CircuitBreaker.State toState = event.getStateTransition().getToState();
            if (toState == CircuitBreaker.State.OPEN) {
                log.warn("RDS circuit breaker OPEN — stopping FlowReceiver (backpressure): destination={}",
                        destination);
                stopFlow();
            } else if (toState == CircuitBreaker.State.CLOSED || toState == CircuitBreaker.State.HALF_OPEN) {
                log.info("RDS circuit breaker {} — restarting FlowReceiver: destination={}", toState, destination);
                startFlow();
            }
        });
        log.info("Circuit-breaker backpressure registered: breaker={} destination={}",
                RDS_CIRCUIT_BREAKER_NAME, destination);
    }

    private void stopFlow() {
        if (flowReceiver != null) {
            try {
                flowReceiver.stop();
            } catch (Exception e) {
                log.error("Error stopping FlowReceiver on circuit-breaker OPEN: destination={} error={}",
                        destination, e.getMessage(), e);
            }
        }
    }

    private void startFlow() {
        if (flowReceiver != null && running.get()) {
            try {
                flowReceiver.start();
            } catch (JCSMPException e) {
                log.error("Error restarting FlowReceiver on circuit-breaker close: destination={} error={}",
                        destination, e.getMessage(), e);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Inner classes
    // -------------------------------------------------------------------------

    /**
     * Receives JCSMP messages and dispatches each to the Solace bulkhead executor.
     *
     * <p>ACK contract: {@code message.ackMessage()} is called only in the success
     * path of the executor task — never in {@code finally}, never before
     * {@link MessageProcessingService#processMessage} returns.
     *
     * <p>On executor queue saturation, {@link ThreadPoolExecutor.CallerRunsPolicy}
     * runs the task on the JCSMP receiver thread, blocking it and preventing
     * new message delivery until capacity is available.
     */
    private final class SolaceXmlMessageListener implements XMLMessageListener {

        @Override
        public void onReceive(final BytesXMLMessage message) {
            final String messageId = resolveMessageId(message);
            final String correlationId = resolveCorrelationId(message);

            log.debug("Message received, dispatching to executor: messageId={} destination={}",
                    messageId, destination);

            processingExecutor.execute(() -> {
                MDC.put("messageId", messageId);
                MDC.put("correlationId", correlationId);
                MDC.put("destination", destination);
                try {
                    processingService.processMessage(message);

                    // ACK only after @Transactional commit inside processingService
                    message.ackMessage();
                    log.info("Message processed and acknowledged: messageId={} correlationId={} destination={}",
                            messageId, correlationId, destination);

                } catch (Exception e) {
                    // Not acking — message stays on broker for redelivery within prefetch window
                    log.error("Message processing failed — not acknowledging (redelivery pending): "
                                    + "messageId={} destination={} errorType={} error={}",
                            messageId, destination, e.getClass().getSimpleName(), e.getMessage(), e);
                } finally {
                    MDC.clear();
                }
            });
        }

        @Override
        public void onException(final JCSMPException exception) {
            log.error("JCSMP FlowReceiver exception: destination={} error={}",
                    destination, exception.getMessage(), exception);
        }

        private String resolveMessageId(final BytesXMLMessage message) {
            final String id = message.getMessageId();
            return (id != null && !id.isBlank()) ? id : "unknown-" + UUID.randomUUID();
        }

        private String resolveCorrelationId(final BytesXMLMessage message) {
            final String cid = message.getCorrelationId();
            return (cid != null && !cid.isBlank()) ? cid : UUID.randomUUID().toString();
        }
    }

    /**
     * Logs all FlowReceiver lifecycle events for operational visibility.
     *
     * <p>FLOW_DOWN and FLOW_RECONNECTING are WARN — they indicate connectivity
     * disruption but JCSMP's reconnect logic (reconnectRetries=-1) handles recovery
     * automatically. FLOW_UP is INFO — a state transition worth recording.
     */
    private final class SolaceFlowEventHandler implements FlowEventHandler {

        @Override
        public void handleEvent(final Object source, final FlowEventArgs event) {
            final String eventName = event.getEvent() != null
                    ? event.getEvent().toString()
                    : "UNKNOWN";

            if ("FLOW_UP".equals(eventName)) {
                log.info("Flow UP: destination={} info={}", destination, event.getInfo());
            } else if ("FLOW_DOWN".equals(eventName)) {
                log.warn("Flow DOWN: destination={} responseCode={} info={}",
                        destination, event.getResponseCode(), event.getInfo());
            } else if ("FLOW_RECONNECTING".equals(eventName)) {
                log.warn("Flow RECONNECTING: destination={} info={}", destination, event.getInfo());
            } else {
                log.debug("Flow event: event={} destination={} info={}",
                        eventName, destination, event.getInfo());
            }
        }
    }
}
