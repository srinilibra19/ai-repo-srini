package com.middleware.hermes.config;

import com.solacesystems.jcsmp.EndpointProperties;
import com.solacesystems.jcsmp.JCSMPException;
import com.solacesystems.jcsmp.JCSMPFactory;
import com.solacesystems.jcsmp.JCSMPProperties;
import com.solacesystems.jcsmp.JCSMPSession;
import com.solacesystems.jcsmp.Queue;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * JCSMP session and queue endpoint configuration.
 *
 * <p>Creates and connects the {@link JCSMPSession} bean used by
 * {@link com.middleware.hermes.messaging.SolaceMessageConsumer} to bind a
 * {@code FlowReceiver} to the {@code hermes.flightschedules} queue.
 *
 * <p>All connection properties are read from environment variables injected by
 * ESO → K8s Secret (AWS) or from {@code application-local.yml} (local dev).
 * No credentials appear in this class.
 *
 * <p>TLS/mTLS settings (per REQ-SOL-004):
 * <ul>
 *   <li>Protocol forced to {@code TLSv1.2} — no TLS 1.0/1.1</li>
 *   <li>Cipher suites restricted to ECDHE+AES256/AES128 GCM families</li>
 *   <li>Client keystore (PKCS12) mounted from K8s Secret volume in AWS;
 *       from {@code local-dev/certs/} in local dev</li>
 *   <li>Truststore (JKS) same mounting strategy</li>
 * </ul>
 *
 * <p>Resilience settings (per {@code application.yml}):
 * <ul>
 *   <li>{@code reconnectRetries = -1} — infinite reconnection</li>
 *   <li>{@code reconnectRetryWaitMillis = 3000} — 3 s between attempts</li>
 *   <li>{@code subAckWindowSize = 32} — prefetch window</li>
 * </ul>
 */
@Slf4j
@Configuration
public class SolaceConfig {

    // -------------------------------------------------------------------------
    // Connection properties — injected from environment variables
    // -------------------------------------------------------------------------

    private final String host;
    private final String msgVpn;
    private final String clientUsername;
    private final String clientPassword;
    private final String clientName;

    // -------------------------------------------------------------------------
    // TLS / mTLS properties
    // -------------------------------------------------------------------------

    private final String sslTrustStore;
    private final String sslTrustStorePassword;
    private final String sslKeyStore;
    private final String sslKeyStorePassword;

    // -------------------------------------------------------------------------
    // Queue configuration
    // -------------------------------------------------------------------------

    private final String queueName;

    // -------------------------------------------------------------------------
    // Resilience / performance tuning — values defined in application.yml
    // -------------------------------------------------------------------------

    private final int reconnectRetries;
    private final int reconnectRetryWaitMillis;
    private final int subAckWindowSize;
    private final int socketRcvbufSize;
    private final int compressionLevel;

    public SolaceConfig(
            @Value("${solace.java.host}") String host,
            @Value("${solace.java.msg-vpn}") String msgVpn,
            @Value("${solace.java.client-username}") String clientUsername,
            @Value("${solace.java.client-password}") String clientPassword,
            @Value("${solace.java.client-name}") String clientName,
            @Value("${solace.java.ssl-trust-store}") String sslTrustStore,
            @Value("${solace.java.ssl-trust-store-password}") String sslTrustStorePassword,
            @Value("${solace.java.ssl-key-store}") String sslKeyStore,
            @Value("${solace.java.ssl-key-store-password}") String sslKeyStorePassword,
            @Value("${hermes.solace.queue-name}") String queueName,
            @Value("${solace.java.reconnect-retries:-1}") int reconnectRetries,
            @Value("${solace.java.reconnect-retry-wait-millis:3000}") int reconnectRetryWaitMillis,
            @Value("${solace.java.sub-ack-window-size:32}") int subAckWindowSize,
            @Value("${solace.java.socket-rcvbuf-size:131072}") int socketRcvbufSize,
            @Value("${solace.java.compression-level:6}") int compressionLevel) {
        this.host = host;
        this.msgVpn = msgVpn;
        this.clientUsername = clientUsername;
        this.clientPassword = clientPassword;
        this.clientName = clientName;
        this.sslTrustStore = sslTrustStore;
        this.sslTrustStorePassword = sslTrustStorePassword;
        this.sslKeyStore = sslKeyStore;
        this.sslKeyStorePassword = sslKeyStorePassword;
        this.queueName = queueName;
        this.reconnectRetries = reconnectRetries;
        this.reconnectRetryWaitMillis = reconnectRetryWaitMillis;
        this.subAckWindowSize = subAckWindowSize;
        this.socketRcvbufSize = socketRcvbufSize;
        this.compressionLevel = compressionLevel;
    }

    // -------------------------------------------------------------------------
    // JCSMPSession bean
    // -------------------------------------------------------------------------

    /**
     * Creates and connects the JCSMP session.
     *
     * <p>The session is shared across the application lifetime.
     * {@link com.middleware.hermes.messaging.SolaceMessageConsumer} uses it
     * to create a {@code FlowReceiver}.
     *
     * @return a connected {@link JCSMPSession}
     * @throws JCSMPException if the session cannot connect on startup
     */
    @Bean
    public JCSMPSession jcsmpSession() throws JCSMPException {
        final JCSMPProperties props = new JCSMPProperties();

        // --- Core connection ---
        props.setProperty(JCSMPProperties.HOST, host);
        props.setProperty(JCSMPProperties.VPN_NAME, msgVpn);
        props.setProperty(JCSMPProperties.USERNAME, clientUsername);
        props.setProperty(JCSMPProperties.PASSWORD, clientPassword);
        props.setProperty(JCSMPProperties.CLIENT_NAME, clientName);

        // --- TLS ---
        props.setProperty(JCSMPProperties.SSL_PROTOCOL, "TLSv1.2");
        props.setProperty(JCSMPProperties.SSL_CIPHER_SUITES,
                "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,"
                + "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,"
                + "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,"
                + "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256");
        props.setProperty(JCSMPProperties.SSL_VALIDATE_CERTIFICATE, true);

        // --- mTLS client certificate ---
        props.setProperty(JCSMPProperties.SSL_KEY_STORE, sslKeyStore);
        props.setProperty(JCSMPProperties.SSL_KEY_STORE_FORMAT, "PKCS12");
        props.setProperty(JCSMPProperties.SSL_KEY_STORE_PASSWORD, sslKeyStorePassword);
        props.setProperty(JCSMPProperties.SSL_TRUST_STORE, sslTrustStore);
        props.setProperty(JCSMPProperties.SSL_TRUST_STORE_PASSWORD, sslTrustStorePassword);

        // --- Resilience (values from application.yml) ---
        props.setProperty(JCSMPProperties.RECONNECT_RETRIES, reconnectRetries);
        props.setProperty(JCSMPProperties.RECONNECT_RETRY_WAIT_IN_MILLIS, reconnectRetryWaitMillis);

        // --- Flow / performance tuning (values from application.yml) ---
        props.setProperty(JCSMPProperties.SUB_ACK_WINDOW_SIZE, subAckWindowSize);
        props.setProperty(JCSMPProperties.SOCKET_RCVBUF_SIZE, socketRcvbufSize);
        props.setProperty(JCSMPProperties.COMPRESSION_LEVEL, compressionLevel);

        // --- ACK mode: individual per-message (never auto or client-bulk) ---
        props.setProperty(JCSMPProperties.MESSAGE_ACK_MODE,
                JCSMPProperties.SUPPORTED_MESSAGE_ACK_CLIENT_INDIVIDUAL);

        log.info("Creating JCSMP session: host={} vpn={} clientName={}", host, msgVpn, clientName);

        final JCSMPSession session = JCSMPFactory.onlyInstance().createSession(props);
        session.connect();
        log.info("JCSMP session connected: clientName={}", clientName);

        return session;
    }

    /**
     * Queue endpoint bean — the durable queue on the Solace broker.
     * Used by {@link com.middleware.hermes.messaging.SolaceMessageConsumer}
     * to bind the {@code FlowReceiver}.
     *
     * @return the {@link Queue} endpoint handle
     */
    @Bean
    public Queue solaceQueue() {
        return JCSMPFactory.onlyInstance().createQueue(queueName);
    }

    /**
     * Endpoint properties for the flow binding.
     * Sets access type to non-exclusive (competing consumers for KEDA scale-out).
     *
     * @return configured {@link EndpointProperties}
     */
    @Bean
    public EndpointProperties flowEndpointProperties() {
        final EndpointProperties props = new EndpointProperties();
        props.setAccessType(EndpointProperties.ACCESSTYPE_NONEXCLUSIVE);
        return props;
    }
}
