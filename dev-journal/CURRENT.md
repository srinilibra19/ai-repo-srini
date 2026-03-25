# Active Story Handoff
Last updated : 2026-03-25
Story        : US-E5-002 — JCSMP FlowReceiver with mTLS configuration
Status       : IN_PROGRESS
Sprint       : 3–4

## Acceptance Criteria Status
- [~] SolaceConfig.java: creates JCSMPSession with all properties from REQ-SOL-004 (written, reviews pending)
- [~] TLS configuration: SSL_PROTOCOL = "TLSv1.2", cipher suites restricted (in SolaceConfig.java)
- [~] mTLS: SSL_KEY_STORE (PKCS12), SSL_KEY_STORE_PASSWORD, SSL_TRUST_STORE, SSL_TRUST_STORE_PASSWORD (in SolaceConfig.java)
- [~] client-name = aws-hermes-flightschedules-{pod-uid} (in SolaceConfig.java via ${solace.java.client-name})
- [~] reconnectRetries = -1, reconnectRetryWaitInMillis = 3000 (in SolaceConfig.java)
- [~] subAckWindowSize = 32, socketReceiveBufferSize = 131072, compressionLevel = 6 (in SolaceConfig.java)
- [ ] FlowReceiver bound to queue hermes.flightschedules with SUPPORTED_MESSAGE_ACK_CLIENT_INDIVIDUAL
- [ ] XMLMessageListener.onReceive() dispatches messages to processing thread pool
- [ ] FlowEventHandler logs flow lifecycle events
- [ ] Flow starts on application startup; stops on SIGTERM
- [ ] Local test: app connects to Docker Compose Solace with self-signed certs

## Sub-task Status
- [~] ST-01: SolaceConfig.java — JCSMP session + mTLS beans → WRITTEN, reviews pending
- [ ] ST-02: SolaceMessageConsumer.java — FlowReceiver + XMLMessageListener + FlowEventHandler + lifecycle
- [ ] ST-03: SolaceConfigTest.java — unit tests for SolaceConfig beans
- [ ] ST-04: SolaceMessageConsumerTest.java — unit tests for SolaceMessageConsumer
- [ ] ST-05: application.yml — add hermes.solace.queue-name property
- [ ] ST-06: application-local.yml — local Solace connection properties

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| src/main/java/com/middleware/hermes/config/SolaceConfig.java | WRITTEN | 3 beans: jcsmpSession, solaceQueue, flowEndpointProperties. Reviews pending. |

## Key Interfaces Defined
- SolaceMessageConsumer will depend on a `MessageProcessingService` interface (to be defined in ST-02) to avoid blocker on E6-004

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| SolaceConfig.java (not SolaceJcsmpConfig.java) | CLAUDE.md folder structure specifies SolaceConfig.java | backlog name SolaceJcsmpConfig |
| EndpointProperties.ACCESSTYPE_NONEXCLUSIVE | KEDA scale-out requires competing consumers | ACCESSTYPE_EXCLUSIVE |
| MessageProcessingService interface injected | Avoids blocker on E6-004 which hasn't been implemented yet | Concrete class injection |

## Open Questions
- hermes.solace.queue-name property needs adding to application.yml base config (ST-05)
- POD_UID Downward API env var: client-name in application-aws.yml should reference ${POD_UID} — verify if already set

## Exact Next Step
Run /code-reviewer and /security-reviewer on src/main/java/com/middleware/hermes/config/SolaceConfig.java, present findings to user, wait for Yes/No before proceeding to ST-02.

## Context to Load on Resume
1. dev-journal/CURRENT.md (already reading this)
2. src/main/java/com/middleware/hermes/config/SolaceConfig.java — current JCSMP session implementation
3. src/main/resources/application-aws.yml — Solace prod property names
CLAUDE.md sections needed: Solace/JCSMP standards, Java/Spring Boot standards, Security standards
