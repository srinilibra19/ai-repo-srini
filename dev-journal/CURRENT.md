# Active Story Handoff
Last updated : 2026-03-25
Story        : US-E5-002 — JCSMP FlowReceiver with mTLS configuration
Status       : IN_PROGRESS
Sprint       : 3–4

## Acceptance Criteria Status
- [x] SolaceConfig.java: creates JCSMPSession with all properties from REQ-SOL-004
- [x] TLS configuration: SSL_PROTOCOL = "TLSv1.2", cipher suites restricted
- [x] mTLS: SSL_KEY_STORE (PKCS12), SSL_KEY_STORE_PASSWORD, SSL_TRUST_STORE, SSL_TRUST_STORE_PASSWORD
- [x] client-name = aws-hermes-flightschedules-{pod-uid} (via ${solace.java.client-name} → ${SOLACE_CLIENT_NAME})
- [x] reconnectRetries = -1, reconnectRetryWaitInMillis = 3000 (from application.yml)
- [x] subAckWindowSize = 32, socketReceiveBufferSize = 131072, compressionLevel = 6 (from application.yml)
- [x] FlowReceiver bound to queue hermes.flightschedules with SUPPORTED_MESSAGE_ACK_CLIENT_INDIVIDUAL
- [x] XMLMessageListener.onReceive() dispatches messages to processing thread pool
- [x] FlowEventHandler logs flow lifecycle events
- [x] Flow starts on application startup (SmartLifecycle.start()); stops on SIGTERM (SmartLifecycle.stop())
- [ ] Local test: app connects to Docker Compose Solace with self-signed certs (requires application-local.yml — ST-06)

## Sub-task Status
- [x] ST-01: SolaceConfig.java — JCSMP session + mTLS beans → DONE
- [x] ST-02: MessageProcessingService.java + SolaceMessageConsumer.java → DONE
- [ ] ST-03: SolaceConfigTest.java — unit tests for SolaceConfig beans
- [ ] ST-04: SolaceMessageConsumerTest.java — unit tests for SolaceMessageConsumer
- [ ] ST-05: application.yml — hermes.solace.* properties → DONE (applied during ST-02 reviews)
- [ ] ST-06: application-local.yml — local Solace connection properties

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| src/main/java/com/middleware/hermes/config/SolaceConfig.java | DONE | Constructor injection, 3 beans, all values from yml |
| src/main/resources/application.yml | DONE | Added 5 Solace tuning props + 4 hermes.solace.* props |
| src/main/java/com/middleware/hermes/processing/MessageProcessingService.java | DONE | Interface contract — implementations in E6-004 |
| src/main/java/com/middleware/hermes/messaging/SolaceMessageConsumer.java | DONE | SmartLifecycle, FlowReceiver, XMLMessageListener, FlowEventHandler, circuit-breaker backpressure |

## Key Interfaces Defined
MessageProcessingService (processing package):
  void processMessage(BytesXMLMessage message)
  — caller ACKs after return; implementations must be @Transactional
  — throws MessageValidationException, DuplicateMessageException (unchecked)

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| SmartLifecycle.DEFAULT_PHASE | Starts last (after DB ready), stops first (before DB pool closes) | Custom lower phase |
| ThreadPoolExecutor.CallerRunsPolicy | Natural backpressure: JCSMP thread blocks when pool saturated | Discard / AbortPolicy |
| processingExecutor created in start() | Lifecycle-scoped — must be fresh on restart after circuit-breaker reset | Spring @Bean executor |
| FlowEvent compared via .equals(toString) | FlowEvent may not be Java enum in all JCSMP versions | switch expression |
| session.closeSession() in stop() | Prevents JCSMP background thread leak | Let Spring destroy bean |

## Open Questions
- CloudWatch Alarms for new failure modes (FLOW_DOWN, processing failures, CB OPEN) — deferred to monitoring story (Sprint 8). Noted as Low security finding A09.3.
- application-local.yml Solace properties — ST-06 pending.

## Deviations from CLAUDE.md
| Rule | Deviation | Justification |
|------|-----------|---------------|
| "write tests alongside implementation" | ST-03/ST-04 tests deferred | Tests are tracked sub-tasks; ST-02 was large enough alone |

## Exact Next Step
Implement ST-03: write SolaceConfigTest.java — mock JCSMPFactory to test jcsmpSession(), solaceQueue(), and flowEndpointProperties() beans; cover happy path and JCSMPException failure path.

## Context to Load on Resume
1. dev-journal/CURRENT.md (already reading this)
2. src/main/java/com/middleware/hermes/config/SolaceConfig.java — constructor signature (15 params)
3. src/main/java/com/middleware/hermes/messaging/SolaceMessageConsumer.java — constructor signature
CLAUDE.md sections needed: Java/Spring Boot standards, Testing standards
