package com.middleware.hermes.unit.messaging;

import com.middleware.hermes.messaging.SolaceMessageConsumer;
import com.middleware.hermes.processing.MessageProcessingService;
import com.solacesystems.jcsmp.BytesXMLMessage;
import com.solacesystems.jcsmp.ConsumerFlowProperties;
import com.solacesystems.jcsmp.EndpointProperties;
import com.solacesystems.jcsmp.FlowEventHandler;
import com.solacesystems.jcsmp.FlowReceiver;
import com.solacesystems.jcsmp.JCSMPException;
import com.solacesystems.jcsmp.JCSMPSession;
import com.solacesystems.jcsmp.Queue;
import com.solacesystems.jcsmp.XMLMessageListener;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.circuitbreaker.event.CircuitBreakerOnStateTransitionEvent;
import io.github.resilience4j.core.EventConsumer;
import io.github.resilience4j.core.EventPublisher;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link SolaceMessageConsumer}.
 *
 * <p>All JCSMP collaborators are mocked. Tests exercise:
 * <ul>
 *   <li>Lifecycle: start → isRunning, idempotent start, start failure</li>
 *   <li>ACK contract: processMessage success → ackMessage; failure → no ack</li>
 *   <li>Circuit-breaker backpressure: OPEN → flowReceiver.stop(); CLOSED → flowReceiver.start()</li>
 *   <li>Graceful stop: executor drains, session closed</li>
 * </ul>
 *
 * <p>Note: {@code FOR UPDATE SKIP LOCKED} outbox queries are tested via Testcontainers
 * in the integration test suite (US-E11-002) — H2 does not support that hint.
 */
@ExtendWith(MockitoExtension.class)
class SolaceMessageConsumerTest {

    private static final String DESTINATION = "flightschedules";
    private static final int THREAD_POOL_SIZE = 2;
    private static final long STOP_TIMEOUT_MILLIS = 5000L;

    @Mock private JCSMPSession session;
    @Mock private Queue queue;
    @Mock private EndpointProperties endpointProperties;
    @Mock private MessageProcessingService processingService;
    @Mock private CircuitBreakerRegistry circuitBreakerRegistry;
    @Mock private CircuitBreaker circuitBreaker;
    @Mock private EventPublisher<EventConsumer<CircuitBreakerOnStateTransitionEvent>> cbEventPublisher;
    @Mock private FlowReceiver flowReceiver;

    private SolaceMessageConsumer consumer;

    @BeforeEach
    void setUp() throws JCSMPException {
        when(circuitBreakerRegistry.circuitBreaker(anyString())).thenReturn(circuitBreaker);
        when(circuitBreaker.getEventPublisher()).thenReturn((CircuitBreaker.EventPublisher) cbEventPublisher);
        when(session.createFlow(
                any(XMLMessageListener.class),
                any(ConsumerFlowProperties.class),
                any(EndpointProperties.class),
                any(FlowEventHandler.class))).thenReturn(flowReceiver);
        when(queue.getName()).thenReturn("hermes." + DESTINATION);

        consumer = new SolaceMessageConsumer(
                session, queue, endpointProperties, processingService,
                circuitBreakerRegistry, DESTINATION, THREAD_POOL_SIZE, STOP_TIMEOUT_MILLIS);
    }

    // -------------------------------------------------------------------------
    // Lifecycle — start()
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("start() — binds FlowReceiver, starts it, and sets isRunning=true")
    void start_happyPath_flowReceiverStartedAndRunning() throws JCSMPException {
        consumer.start();

        verify(session).createFlow(
                any(XMLMessageListener.class),
                any(ConsumerFlowProperties.class),
                any(EndpointProperties.class),
                any(FlowEventHandler.class));
        verify(flowReceiver).start();
        assertThat(consumer.isRunning()).isTrue();
    }

    @Test
    @DisplayName("start() — idempotent: second call does not rebind or restart flow")
    void start_calledTwice_idempotent() throws JCSMPException {
        consumer.start();
        consumer.start();

        // createFlow and flowReceiver.start() called only once
        verify(session).createFlow(any(), any(), any(), any());
        verify(flowReceiver).start();
    }

    @Test
    @DisplayName("start() — JCSMPException on createFlow propagates as IllegalStateException")
    void start_createFlowThrows_wrappedAsIllegalStateException() throws JCSMPException {
        when(session.createFlow(any(), any(), any(), any()))
                .thenThrow(new JCSMPException("broker refused flow bind"));

        assertThatThrownBy(() -> consumer.start())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("FlowReceiver failed to start")
                .hasCauseInstanceOf(JCSMPException.class);

        assertThat(consumer.isRunning()).isFalse();
    }

    // -------------------------------------------------------------------------
    // Lifecycle — stop()
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("stop() — stops FlowReceiver, shuts down executor, closes session")
    void stop_afterStart_flowStoppedAndSessionClosed() throws JCSMPException {
        consumer.start();
        consumer.stop();

        verify(flowReceiver).stop();
        verify(session).closeSession();
        assertThat(consumer.isRunning()).isFalse();
    }

    @Test
    @DisplayName("stop() — idempotent: second call does not close session again")
    void stop_calledTwice_idempotent() throws JCSMPException {
        consumer.start();
        consumer.stop();
        consumer.stop();

        // session.closeSession() called only once
        verify(session).closeSession();
    }

    // -------------------------------------------------------------------------
    // ACK contract — success path
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("onReceive — processMessage success → message.ackMessage() called")
    void onReceive_processingSuccess_messageAcknowledged() throws JCSMPException, InterruptedException {
        consumer.start();

        final ArgumentCaptor<XMLMessageListener> listenerCaptor =
                ArgumentCaptor.forClass(XMLMessageListener.class);
        verify(session).createFlow(listenerCaptor.capture(), any(), any(), any());

        final XMLMessageListener listener = listenerCaptor.getValue();
        final BytesXMLMessage message = mockMessage("msg-001", "corr-001");

        listener.onReceive(message);
        awaitExecutorDrain();

        verify(processingService).processMessage(message);
        verify(message).ackMessage();
    }

    // -------------------------------------------------------------------------
    // ACK contract — failure path
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("onReceive — processMessage throws → message NOT acknowledged (stays on broker)")
    void onReceive_processingFails_messageNotAcknowledged() throws JCSMPException, InterruptedException {
        consumer.start();

        final ArgumentCaptor<XMLMessageListener> listenerCaptor =
                ArgumentCaptor.forClass(XMLMessageListener.class);
        verify(session).createFlow(listenerCaptor.capture(), any(), any(), any());

        final XMLMessageListener listener = listenerCaptor.getValue();
        final BytesXMLMessage message = mockMessage("msg-002", "corr-002");
        doThrow(new RuntimeException("DB unavailable")).when(processingService).processMessage(message);

        listener.onReceive(message);
        awaitExecutorDrain();

        verify(processingService).processMessage(message);
        verify(message, never()).ackMessage();
    }

    // -------------------------------------------------------------------------
    // Circuit-breaker backpressure
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("circuit breaker OPEN → flowReceiver.stop() called (backpressure)")
    void circuitBreakerOpen_flowReceiverStopped() throws JCSMPException {
        consumer.start();

        final ArgumentCaptor<EventConsumer<CircuitBreakerOnStateTransitionEvent>> callbackCaptor =
                ArgumentCaptor.forClass(EventConsumer.class);
        verify(cbEventPublisher).onStateTransition(callbackCaptor.capture());

        final EventConsumer<CircuitBreakerOnStateTransitionEvent> callback = callbackCaptor.getValue();
        callback.consumeEvent(stateTransitionEvent(CircuitBreaker.State.CLOSED, CircuitBreaker.State.OPEN));

        verify(flowReceiver).stop();
    }

    @Test
    @DisplayName("circuit breaker CLOSED → flowReceiver.start() called (backpressure released)")
    void circuitBreakerClosed_flowReceiverRestarted() throws JCSMPException {
        consumer.start();

        final ArgumentCaptor<EventConsumer<CircuitBreakerOnStateTransitionEvent>> callbackCaptor =
                ArgumentCaptor.forClass(EventConsumer.class);
        verify(cbEventPublisher).onStateTransition(callbackCaptor.capture());

        final EventConsumer<CircuitBreakerOnStateTransitionEvent> callback = callbackCaptor.getValue();
        // Simulate: OPEN → CLOSED recovery
        callback.consumeEvent(stateTransitionEvent(CircuitBreaker.State.OPEN, CircuitBreaker.State.CLOSED));

        // flowReceiver.start() called once on consumer.start() + once on CB close
        verify(flowReceiver, org.mockito.Mockito.times(2)).start();
    }

    @Test
    @DisplayName("circuit breaker HALF_OPEN → flowReceiver.start() called (probe traffic allowed)")
    void circuitBreakerHalfOpen_flowReceiverRestarted() throws JCSMPException {
        consumer.start();

        final ArgumentCaptor<EventConsumer<CircuitBreakerOnStateTransitionEvent>> callbackCaptor =
                ArgumentCaptor.forClass(EventConsumer.class);
        verify(cbEventPublisher).onStateTransition(callbackCaptor.capture());

        final EventConsumer<CircuitBreakerOnStateTransitionEvent> callback = callbackCaptor.getValue();
        callback.consumeEvent(stateTransitionEvent(CircuitBreaker.State.OPEN, CircuitBreaker.State.HALF_OPEN));

        verify(flowReceiver, org.mockito.Mockito.times(2)).start();
    }

    // -------------------------------------------------------------------------
    // SmartLifecycle phase
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("getPhase() — returns DEFAULT_PHASE (starts last, stops first)")
    void getPhase_returnsDefaultPhase() {
        assertThat(consumer.getPhase()).isEqualTo(Integer.MAX_VALUE);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static BytesXMLMessage mockMessage(final String messageId, final String correlationId) {
        final BytesXMLMessage message = mock(BytesXMLMessage.class);
        when(message.getMessageId()).thenReturn(messageId);
        when(message.getCorrelationId()).thenReturn(correlationId);
        return message;
    }

    private static CircuitBreakerOnStateTransitionEvent stateTransitionEvent(
            final CircuitBreaker.State from, final CircuitBreaker.State to) {
        final CircuitBreaker.StateTransition transition = mock(CircuitBreaker.StateTransition.class);
        when(transition.getFromState()).thenReturn(from);
        when(transition.getToState()).thenReturn(to);

        final CircuitBreakerOnStateTransitionEvent event =
                mock(CircuitBreakerOnStateTransitionEvent.class);
        when(event.getStateTransition()).thenReturn(transition);
        return event;
    }

    // Give the processing executor time to pick up and complete the submitted task.
    private void awaitExecutorDrain() throws InterruptedException {
        Thread.sleep(200);
    }
}
