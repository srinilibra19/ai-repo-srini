package com.middleware.hermes.unit.config;

import com.middleware.hermes.config.SolaceConfig;
import com.solacesystems.jcsmp.EndpointProperties;
import com.solacesystems.jcsmp.JCSMPException;
import com.solacesystems.jcsmp.JCSMPFactory;
import com.solacesystems.jcsmp.JCSMPProperties;
import com.solacesystems.jcsmp.JCSMPSession;
import com.solacesystems.jcsmp.Queue;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link SolaceConfig}.
 *
 * <p>JCSMPFactory is a static singleton — tests use Mockito's {@code mockStatic} to
 * intercept {@code JCSMPFactory.onlyInstance()} calls without starting a real broker.
 */
class SolaceConfigTest {

    // -------------------------------------------------------------------------
    // Test constants — match application.yml defaults
    // -------------------------------------------------------------------------

    private static final String HOST = "tcps://solace.test:55443";
    private static final String MSG_VPN = "test-vpn";
    private static final String USERNAME = "test-user";
    private static final String PASSWORD = "test-password";
    private static final String CLIENT_NAME = "aws-hermes-flightschedules-test-pod-uid";
    private static final String TRUST_STORE = "/mnt/certs/truststore.jks";
    private static final String TRUST_STORE_PASSWORD = "ts-password";
    private static final String KEY_STORE = "/mnt/certs/keystore.p12";
    private static final String KEY_STORE_PASSWORD = "ks-password";
    private static final String QUEUE_NAME = "hermes.flightschedules";
    private static final int RECONNECT_RETRIES = -1;
    private static final int RECONNECT_RETRY_WAIT_MILLIS = 3000;
    private static final int SUB_ACK_WINDOW_SIZE = 32;
    private static final int SOCKET_RCVBUF_SIZE = 131072;
    private static final int COMPRESSION_LEVEL = 6;

    // -------------------------------------------------------------------------
    // Mocks
    // -------------------------------------------------------------------------

    private MockedStatic<JCSMPFactory> jcsmpFactoryMock;
    private JCSMPFactory mockFactory;
    private JCSMPSession mockSession;
    private Queue mockQueue;

    @BeforeEach
    void setUp() {
        mockFactory = mock(JCSMPFactory.class);
        mockSession = mock(JCSMPSession.class);
        mockQueue = mock(Queue.class);

        jcsmpFactoryMock = mockStatic(JCSMPFactory.class);
        jcsmpFactoryMock.when(JCSMPFactory::onlyInstance).thenReturn(mockFactory);
    }

    @AfterEach
    void tearDown() {
        jcsmpFactoryMock.close();
    }

    // -------------------------------------------------------------------------
    // Helper
    // -------------------------------------------------------------------------

    private SolaceConfig buildConfig() {
        return new SolaceConfig(
                HOST, MSG_VPN, USERNAME, PASSWORD, CLIENT_NAME,
                TRUST_STORE, TRUST_STORE_PASSWORD,
                KEY_STORE, KEY_STORE_PASSWORD,
                QUEUE_NAME,
                RECONNECT_RETRIES, RECONNECT_RETRY_WAIT_MILLIS,
                SUB_ACK_WINDOW_SIZE, SOCKET_RCVBUF_SIZE, COMPRESSION_LEVEL);
    }

    // -------------------------------------------------------------------------
    // jcsmpSession() — happy path
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("jcsmpSession() — creates and connects session with all properties set")
    void jcsmpSession_happyPath_createsAndConnectsSession() throws JCSMPException {
        when(mockFactory.createSession(any(JCSMPProperties.class))).thenReturn(mockSession);

        final JCSMPSession result = buildConfig().jcsmpSession();

        assertThat(result).isSameAs(mockSession);
        verify(mockSession).connect();
    }

    @Test
    @DisplayName("jcsmpSession() — passes TLSv1.2 protocol and INDIVIDUAL_ACK mode")
    void jcsmpSession_setsRequiredTlsAndAckProperties() throws JCSMPException {
        when(mockFactory.createSession(any(JCSMPProperties.class))).thenAnswer(invocation -> {
            final JCSMPProperties props = invocation.getArgument(0);
            assertThat(props.getStringProperty(JCSMPProperties.SSL_PROTOCOL)).isEqualTo("TLSv1.2");
            assertThat(props.getBooleanProperty(JCSMPProperties.SSL_VALIDATE_CERTIFICATE)).isTrue();
            assertThat(props.getStringProperty(JCSMPProperties.SSL_KEY_STORE_FORMAT)).isEqualTo("PKCS12");
            assertThat(props.getStringProperty(JCSMPProperties.MESSAGE_ACK_MODE))
                    .isEqualTo(JCSMPProperties.SUPPORTED_MESSAGE_ACK_CLIENT_INDIVIDUAL);
            assertThat((int) props.getIntegerProperty(JCSMPProperties.RECONNECT_RETRIES)).isEqualTo(-1);
            assertThat((int) props.getIntegerProperty(JCSMPProperties.SUB_ACK_WINDOW_SIZE)).isEqualTo(32);
            return mockSession;
        });

        buildConfig().jcsmpSession();

        verify(mockFactory).createSession(any(JCSMPProperties.class));
    }

    @Test
    @DisplayName("jcsmpSession() — sets client credentials from constructor parameters")
    void jcsmpSession_setsConnectionProperties() throws JCSMPException {
        when(mockFactory.createSession(any(JCSMPProperties.class))).thenAnswer(invocation -> {
            final JCSMPProperties props = invocation.getArgument(0);
            assertThat(props.getStringProperty(JCSMPProperties.HOST)).isEqualTo(HOST);
            assertThat(props.getStringProperty(JCSMPProperties.VPN_NAME)).isEqualTo(MSG_VPN);
            assertThat(props.getStringProperty(JCSMPProperties.USERNAME)).isEqualTo(USERNAME);
            assertThat(props.getStringProperty(JCSMPProperties.CLIENT_NAME)).isEqualTo(CLIENT_NAME);
            assertThat(props.getStringProperty(JCSMPProperties.SSL_KEY_STORE)).isEqualTo(KEY_STORE);
            assertThat(props.getStringProperty(JCSMPProperties.SSL_TRUST_STORE)).isEqualTo(TRUST_STORE);
            return mockSession;
        });

        buildConfig().jcsmpSession();
    }

    // -------------------------------------------------------------------------
    // jcsmpSession() — failure path
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("jcsmpSession() — JCSMPException on createSession propagates to caller")
    void jcsmpSession_createSessionThrows_exceptionPropagates() throws JCSMPException {
        when(mockFactory.createSession(any(JCSMPProperties.class)))
                .thenThrow(new JCSMPException("broker unreachable"));

        assertThatThrownBy(() -> buildConfig().jcsmpSession())
                .isInstanceOf(JCSMPException.class)
                .hasMessageContaining("broker unreachable");
    }

    @Test
    @DisplayName("jcsmpSession() — JCSMPException on connect propagates to caller")
    void jcsmpSession_connectThrows_exceptionPropagates() throws JCSMPException {
        when(mockFactory.createSession(any(JCSMPProperties.class))).thenReturn(mockSession);
        org.mockito.Mockito.doThrow(new JCSMPException("connect failed"))
                .when(mockSession).connect();

        assertThatThrownBy(() -> buildConfig().jcsmpSession())
                .isInstanceOf(JCSMPException.class)
                .hasMessageContaining("connect failed");
    }

    // -------------------------------------------------------------------------
    // solaceQueue()
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("solaceQueue() — returns Queue with configured queue name")
    void solaceQueue_returnsQueueWithCorrectName() {
        when(mockFactory.createQueue(QUEUE_NAME)).thenReturn(mockQueue);

        final Queue result = buildConfig().solaceQueue();

        assertThat(result).isSameAs(mockQueue);
        verify(mockFactory).createQueue(QUEUE_NAME);
    }

    // -------------------------------------------------------------------------
    // flowEndpointProperties()
    // -------------------------------------------------------------------------

    @Test
    @DisplayName("flowEndpointProperties() — access type is NONEXCLUSIVE for competing consumers")
    void flowEndpointProperties_accessTypeIsNonExclusive() {
        final EndpointProperties result = buildConfig().flowEndpointProperties();

        assertThat(result.getAccessType())
                .isEqualTo(EndpointProperties.ACCESSTYPE_NONEXCLUSIVE);
    }
}
