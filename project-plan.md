# Containers with Middleware — Project Plan
## Agile Delivery Plan: Resilient Solace Subscription Layer (MVP: flightschedules destination)

| Field | Value |
|---|---|
| **Version** | 1.0 |
| **Date** | 2026-03-19 |
| **Lead** | Solo Developer (Claude-assisted) |
| **MVP Scope** | Single destination: `flightschedules` |
| **Sprint Length** | 2 weeks |
| **Total Sprints** | 10 (20 weeks) |
| **Platform** | ROSA (Red Hat OpenShift on AWS) — Greenfield | 

---

## 1. Scope Boundary

### In Scope (We Build)
- Local development environment with Solace, PostgreSQL, and LocalStack
- All AWS infrastructure (Terraform, greenfield): VPC, ROSA, RDS, SNS FIFO, SQS FIFO, KMS, Secrets Manager, VPC Endpoints, RDS Proxy, IAM
- Spring Boot 3.x / Java 17 application using Solace JCSMP via mTLS
- Transactional Outbox pattern with PostgreSQL LISTEN/NOTIFY
- Claim-Check pattern for messages > 200 KB (S3 payload store)
- Full resilience stack: circuit breakers, retry, bulkhead, backpressure to Solace
- ROSA container deployment via Helm: HPA, KEDA, PDB, anti-affinity
- Observability: ADOT, CloudWatch metrics/logs, X-Ray tracing, dashboards, alarms
- CI/CD: AWS CodePipeline + CodeBuild
- Load testing: Solace SDKPerf + JMeter
- Multi-AZ DR validation and runbooks

### Out of Scope (Broker-Configured by Customer)
- Section 3.8 broker-side provisioning: queues, client profiles, ACL profiles, topic subscriptions, DMQ, SEMP monitoring user
- Cross-region DR (deferred post-MVP)
- PII handling / pgcrypto (no PII in flight schedule data)
- RDS Proxy toggle: `enable_rds_proxy = true` from day one (see rationale in project notes)

---

## 2. Architecture Summary (MVP)

```
[Solace Broker — Customer-managed]
        |
        | TLS 1.2 + mTLS (client cert auth)
        | JCSMP FlowReceiver
        |
[ROSA Cluster — hermes namespace]
  Deployment: hermes-flightschedules (2-10 pods)
        |
        |--- (single DB transaction) ----> [RDS PostgreSQL Multi-AZ]
        |                                   - audit_messages table
        |                                   - outbox_messages table
        |                                   - LISTEN/NOTIFY trigger
        |
        |--- (Solace ACK after commit) ---> Solace broker
        |
  [Outbox Poller — SKIP LOCKED]
        |
        | (messages > 200KB -> S3 claim-check first)
        |
  [SNS FIFO: hermes-flightschedules.fifo]
        |
  [SQS FIFO: hermes-flightschedules-consumer-a.fifo]
  [SQS FIFO: hermes-flightschedules-consumer-b.fifo]
  [SQS FIFO DLQ: hermes-flightschedules-dlq.fifo]
```

**Key decisions:**
- Authentication: mTLS (client certificate). JCSMP configured with keystore + truststore (PKCS12), both stored in Secrets Manager, synced to K8s Secrets via ESO
- Message delivery: INDIVIDUAL_ACKNOWLEDGE, prefetch=32, sub-ack-window=32
- Reconnection: `reconnectRetries: -1` (infinite), fixed 3s interval
- Local dev: Docker Compose (Solace PubSub+ Standard, PostgreSQL, LocalStack)
- IaC: Terraform (AWS) + Helm (ROSA). Single parameterised module per layer

---

## 3. Epics Overview

| # | Epic | Key Outcome | Sprints |
|---|---|---|---|
| E0 | Local Development Environment | Developer can run full stack locally; write and test code before any AWS deployment | 1 |
| E1 | AWS Foundation Infrastructure | VPC, ROSA, ECR, KMS, S3, IAM, Terraform state — all provisioned via Terraform | 1–2 |
| E2 | Security Baseline | Secrets Manager, ESO, mTLS certificates, NetworkPolicies, RBAC, SCCs | 2–3 |
| E3 | Data Layer | RDS Multi-AZ, schema migrations (Flyway), RDS Proxy, connection pool | 3 |
| E4 | Messaging Infrastructure | SNS FIFO, SQS FIFO, DLQs, KMS encryption, access policies | 3 |
| E5 | Spring Boot Application Foundation | JCSMP integration, mTLS, session management, health indicators, local profile | 3–4 |
| E6 | Core Message Processing | Canonical model, validation, idempotency, transactional outbox, LISTEN/NOTIFY, outbox poller → SNS | 4–5 |
| E7 | Claim-Check Pattern | Large message (>200 KB) detection, S3 storage, reference publishing | 5 |
| E8 | Resilience & Reliability | Circuit breakers, retry/backoff, bulkhead, backpressure, DLQ routing, graceful shutdown | 5–6 |
| E9 | ROSA Container Deployment | Helm chart, probes, anti-affinity, PDB, HPA, KEDA, ConfigMaps, ExternalSecrets | 6–7 |
| E10 | Observability | ADOT DaemonSet, CloudWatch metrics/logs, X-Ray tracing, dashboards, alarms | 7–8 |
| E11 | CI/CD Pipeline | CodePipeline: build → test → scan → container build → deploy staging → deploy prod | 8 |
| E12 | Load Testing | Baseline, burst, reconnection, DB failover, scaling, node-kill scenarios | 9 |
| E13 | DR Validation & Operationalisation | Multi-AZ failover drill, DR runbook, chaos engineering, ops procedures | 9–10 |

---

## 4. Epic Dependency Map

```
E0 (Local Dev)
    └─> E5 (Spring Boot App) ─────────────────┐
                                               │
E1 (AWS Foundation) ─> E2 (Security)          │
        │                    │                 │
        └────────────────────┤                 │
                             ├─> E3 (RDS)      │
                             ├─> E4 (SNS/SQS)  │
                             └─────────────────┴─> E6 (Core Processing)
                                                          │
                                                    E7 (Claim-Check)
                                                          │
                                                    E8 (Resilience)
                                                          │
                                                    E9 (ROSA Deploy)
                                                          │
                                               E10 (Observability)
                                                          │
                                               E11 (CI/CD Pipeline)
                                                          │
                                               E12 (Load Testing)
                                                          │
                                               E13 (DR & Ops)
```

**Critical path:** E0 → E5 → E6 → E8 → E9 → E10 → E11 → E12 → E13
**Parallel workstream:** E1 → E2 → E3/E4 feeds into E6

---

## 5. Sprint Roadmap

### Sprint 1 (Weeks 1–2): Local Dev + AWS Foundation IaC
**Goal:** Developer has a fully working local environment. Terraform foundation is ready. No AWS resources deployed yet — just code + local stack.

| Epic | Stories Delivered |
|---|---|
| E0 | Docker Compose setup (Solace, PostgreSQL, LocalStack); local dev guide; self-signed mTLS certs for local; test publisher script |
| E1 | Terraform state backend (S3 + DynamoDB); VPC module (subnets, NAT GW, IGW); ROSA Terraform module stub; ECR repository; KMS key module; S3 buckets (logs, archive, state) |

**Sprint 1 DoD:** `docker compose up` brings up full local stack; developer can connect to local Solace and publish a test message; Terraform `plan` runs cleanly against empty AWS account.

---

### Sprint 2 (Weeks 3–4): Security Baseline + Data Layer
**Goal:** All secrets and certificates are managed in AWS. RDS is provisioned and schema is deployed.

| Epic | Stories Delivered |
|---|---|
| E1 | VPC Endpoints for SNS, SQS, Secrets Manager, SSM, CloudWatch, X-Ray, KMS, ECR, STS, S3 (Gateway + Interface); Security Groups for ROSA nodes and VPC Endpoints |
| E2 | Secrets Manager secrets for Solace credentials + client cert keystore + truststore; KMS CMK for RDS/SNS/SQS/S3; ESO Terraform module; ROSA namespace `hermes` with ResourceQuota, LimitRange, SCC, RBAC |
| E3 | RDS PostgreSQL Multi-AZ Terraform module; RDS Proxy Terraform module (`enable_rds_proxy = true`); Flyway migration: `audit_messages` table + `outbox_messages` table + NOTIFY trigger; indexes on `message_id`, `status`, `created_at` |

**Sprint 2 DoD:** `terraform apply` provisions RDS and all secrets; ESO syncs secrets to K8s Secrets; Flyway migrations run on first app startup; developer can connect to RDS from local machine via bastion/tunnel.

---

### Sprint 3 (Weeks 5–6): Messaging Infrastructure + Spring Boot Foundation
**Goal:** SNS/SQS infrastructure is ready. Spring Boot app connects to Solace locally with mTLS and receives messages.

| Epic | Stories Delivered |
|---|---|
| E4 | SNS FIFO topic: `hermes-flightschedules.fifo`; SQS FIFO queues: `hermes-flightschedules-consumer-a.fifo`; DLQ FIFO: `hermes-flightschedules-dlq.fifo`; SNS→SQS subscription; KMS encryption; access policies; IAM policy for SNS publish (IRSA role) |
| E5 | Spring Boot 3.x project scaffold (Maven, Java 17, UBI base image); Solace Spring Boot Starter dependency; JCSMP FlowReceiver configuration; mTLS keystore/truststore configuration (local = file, AWS = K8s Secret); SessionEventHandler (log UP/DOWN/RECONNECTING/RECONNECTED); Spring profile: `local` (Docker Compose) and `aws` (ROSA); `/actuator/health` with Solace connection health indicator; structured JSON logging (Logback JSON encoder) |

**Sprint 3 DoD:** App starts locally, connects to Solace Docker container via self-signed mTLS, receives a test `flightschedules` message, logs it with correlation ID, and Spring Actuator reports `UP`.

---

### Sprint 4 (Weeks 7–8): Core Message Processing — Part 1
**Goal:** Full message flow works locally: Solace → audit DB + outbox (single TX) → Solace ACK.

| Epic | Stories Delivered |
|---|---|
| E6 | `FlightScheduleMessage` canonical POJO/DTO (deserialization); JSON Schema + Bean Validation; 200 KB payload size check; idempotent consumer (duplicate detection via `message_id` in audit table); transactional outbox write: audit + outbox in one `@Transactional` method; INDIVIDUAL_ACKNOWLEDGE after DB commit; `LISTEN/NOTIFY` trigger on outbox INSERT; outbox poller (`SELECT ... FOR UPDATE SKIP LOCKED`, 500ms fallback poll) |

**Sprint 4 DoD:** Publish 100 test messages to local Solace; verify all 100 appear in audit table exactly once; verify outbox records created and status transitions to `PUBLISHED`; simulate duplicate by re-publishing same message ID — confirm idempotent skip with audit log.

---

### Sprint 5 (Weeks 9–10): SNS Fanout + Claim-Check + Resilience (Part 1)
**Goal:** Outbox poller publishes to SNS FIFO (locally via LocalStack). Large messages handled via claim-check. Circuit breakers in place.

| Epic | Stories Delivered |
|---|---|
| E6 | Outbox poller → SNS FIFO publish with `MessageDeduplicationId` + `MessageGroupId`; async SNS SDK client; batch publish (up to 10 per `PublishBatch`); `MessageGroupId` strategy documented (destination name as default); audit record updated with `sns_message_id` and status `PUBLISHED` |
| E7 | S3 bucket for large payloads (Terraform module); detect messages > 200 KB after deserialization; upload payload to S3; replace outbox payload with claim-check reference `{s3Uri, payloadSizeBytes, contentType}`; downstream consumers use reference to fetch from S3; S3 bucket lifecycle policy (90-day transition to Glacier, 365-day delete) |
| E8 | Resilience4j circuit breaker on RDS write (open on 50% failure, 30s wait, 5 probe requests); Resilience4j circuit breaker on SNS publish; retry with exponential backoff + jitter (100ms initial, 2x factor, max 10s, ±20% jitter); bulkhead: separate thread pools for Solace consumption, RDS writes, SNS publishes |

**Sprint 5 DoD:** Publish 10 messages > 200 KB; confirm payload in S3, reference in SNS; simulate RDS failure — confirm circuit breaker opens, Solace consumption pauses, no in-memory buffering; circuit closes, consumption resumes. LocalStack SNS/SQS receives all messages.

---

### Sprint 6 (Weeks 11–12): Resilience (Part 2) + ROSA Deployment
**Goal:** Full resilience stack complete. Application deployed to ROSA staging namespace via Helm.

| Epic | Stories Delivered |
|---|---|
| E8 | DLQ routing: messages failing after 3 retries routed to SQS DLQ FIFO and audit status set to `DLQ`; graceful shutdown: SIGTERM handler stops FlowReceiver, completes in-flight processing, flushes outbox, cleanly disconnects from Solace within `terminationGracePeriodSeconds: 60`; backpressure: FlowReceiver stop/start wired to circuit breaker state transitions |
| E9 | Helm chart scaffold with `values-local.yaml`, `values-staging.yaml`, `values-prod.yaml`; Deployment manifest (UBI+JRE17, resource requests/limits, env vars from ConfigMaps + Secrets); livenessProbe + readinessProbe + startupProbe; pod anti-affinity (`topologyKey: topology.kubernetes.io/zone`); Pod Disruption Budget (`minAvailable: 1`); HPA (CPU 70% scale-out, 30% scale-in, 300s stabilisation); ConfigMap from SSM Parameter Store via ESO (Solace host, VPN, destination config); ExternalSecret for keystore + truststore + Solace password |

**Sprint 6 DoD:** `helm install hermes-flightschedules ./helm/hermes -f values-staging.yaml` deploys to ROSA staging; pods reach `Ready` state; Actuator health reports `UP`; readiness probe fails when Solace is disconnected, confirming correct probe wiring; PDB prevents both pods being unavailable during node drain test.

---

### Sprint 7 (Weeks 13–14): KEDA + Observability
**Goal:** Auto-scaling based on outbox backlog. Full observability pipeline working (metrics, logs, traces, dashboards, alarms).

| Epic | Stories Delivered |
|---|---|
| E9 | KEDA ScaledObject: scale on `outbox.pending.count` CloudWatch metric (threshold: 100 pending → add pod); KEDA + HPA coexistence configuration; Cluster Autoscaler configuration (min 3, max 12 worker nodes) |
| E10 | ADOT Collector DaemonSet deployment (via OperatorHub); Micrometer CloudWatch registry for custom metrics (`solace.messages.received`, `solace.messages.processed`, `solace.messages.failed`, `solace.connection.status`, `audit.insert.latency`, `sns.publish.latency`, `outbox.pending.count`, `processing.e2e.latency`); CloudWatch Logs log group `hermes/flightschedules/{env}` with 90-day retention; OpenTelemetry SDK instrumentation (custom spans for Solace receive, RDS TX, SNS publish); X-Ray traces via ADOT exporter; CloudWatch Alarms (all 10 alarms from REQ-MON-010); SEMP monitoring sidecar for `solace.dmq.depth` and queue metrics → CloudWatch |

**Sprint 7 DoD:** KEDA scales pods from 2→4 when outbox backlog is artificially induced; CloudWatch dashboard shows real-time throughput, latency P50/P95/P99, connection status; X-Ray service map shows Solace→App→RDS→SNS trace; Solace-Disconnected alarm fires within 1 minute of connection drop.

---

### Sprint 8 (Weeks 15–16): CI/CD Pipeline
**Goal:** Fully automated pipeline from code commit to production deployment with all quality gates.

| Epic | Stories Delivered |
|---|---|
| E11 | CodeCommit / GitHub source stage; CodeBuild: Maven build + JUnit 5 tests (>80% coverage); SonarQube static analysis; Trivy/Snyk security scan (no high/critical CVEs gate); Docker multi-stage build with UBI+Temurin JRE 17; ECR push + image scan; Testcontainers integration tests (Solace PubSub+ Standard container + PostgreSQL container); abbreviated perf smoke test (SDKPerf, 5 min, 1000 msg/s); `helm upgrade --install` to staging; smoke test on staging (health endpoints + 10-message end-to-end flow); manual approval gate; `helm upgrade` to production with `maxUnavailable: 0`, `maxSurge: 1`; automatic `helm rollback` on readiness probe failure |

**Sprint 8 DoD:** Commit to `main` branch triggers pipeline; pipeline runs all stages in < 20 minutes; smoke test on staging passes; manual approval required for production; a deliberately introduced bug is caught by unit tests or static analysis before reaching staging.

---

### Sprint 9 (Weeks 17–18): Load Testing
**Goal:** All load test scenarios pass success criteria. System validated at 1,000 msg/s sustained and 3,000 msg/s burst.

| Epic | Stories Delivered |
|---|---|
| E12 | Performance test environment setup (dedicated ROSA namespace mirroring production); SDKPerf message generator for `flightschedules` destination; JMeter scripts for HTTP endpoints; Baseline test: 1,000 msg/s for 1 hour → verify P95 < 500ms, zero loss; Burst test: 3,000 msg/s for 15 min → verify P99 < 2s; Endurance/Soak: 800 msg/s for 8 hours → verify no memory leak, no thread exhaustion; Reconnection test: kill Solace container mid-load → verify reconnect + zero loss; DB Failover test: trigger RDS failover mid-load → verify backpressure kicks in + messages recovered after reconnect; Scaling test: ramp load → verify HPA/KEDA scales to 10 pods within 3 min; Node Kill test: terminate a worker node → verify pods reschedule + no message loss |

**Sprint 9 DoD:** All REQ-LT-004 to REQ-LT-011 success criteria met and documented; load test report produced; any performance issues resolved before proceeding.

---

### Sprint 10 (Weeks 19–20): DR Validation & Operationalisation
**Goal:** Multi-AZ DR validated. Runbooks documented and tested. System ready for production handover.

| Epic | Stories Delivered |
|---|---|
| E13 | Multi-AZ failover drill: RDS primary AZ failure → confirm failover < 60s, consumption resumes automatically; AZ outage simulation: evict all pods from one AZ → confirm rescheduling to healthy AZ; DR runbook: Solace disconnect recovery; RDS failover recovery; certificate rotation procedure; destination onboarding procedure (how to add a new destination without code changes); CloudWatch runbook: how to use Logs Insights for troubleshooting; Certificate expiry rotation drill: rotate certificates in Secrets Manager → ESO syncs → rolling pod restart → zero downtime confirmed; Production go-live checklist; tagging audit (all resources tagged: Project, Environment, Owner, CostCenter, Destination); Final security review (Security Hub findings, GuardDuty baseline, Config rules active) |

**Sprint 10 DoD:** DR runbook executed and validated; zero-downtime certificate rotation confirmed; production go-live checklist signed off; all CloudWatch alarms in `OK` state at rest; Security Hub score documented.

---

## 6. Definition of Done (Shared)

Every user story is done when:
- [ ] Code reviewed (self-review + Claude review for this project)
- [ ] Unit tests written and passing (>80% coverage for new code)
- [ ] Integration test covers the happy path and at least one failure path
- [ ] No new high/critical security vulnerabilities (Trivy/Snyk clean)
- [ ] Structured logging added for all new operations (with correlationId, messageId, destination)
- [ ] New CloudWatch metric/alarm added if the story introduces a new failure mode
- [ ] Terraform/Helm changes committed to Git and `terraform plan` is clean
- [ ] Local Docker Compose profile still works after the change
- [ ] Acceptance criteria in the story are verified manually or by automated test

---

## 7. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Solace mTLS certificate format incompatible with JCSMP keystore expectations | Medium | High | Validate certificate chain in Sprint 1 local environment using self-signed certs matching the format specification; document exact PKCS12 structure |
| R2 | ROSA provisioning takes longer than expected (AWS account limits, quota requests) | Medium | High | Start Terraform ROSA module in Sprint 1; raise AWS quota requests early; use local environment in parallel so development is not blocked |
| R3 | LocalStack limitations cause local-to-AWS behaviour divergence | Medium | Medium | Document known LocalStack gaps; write integration tests using Testcontainers against real AWS SDK behaviours; test on staging as early as Sprint 3 |
| R4 | PostgreSQL LISTEN/NOTIFY not reliably delivered under high load | Low | High | Fallback 500ms polling is mandatory (REQ-DB-012); load test LISTEN/NOTIFY latency in Sprint 9 |
| R5 | SNS FIFO throughput limits hit before 1,000 msg/s target | Low | High | High-throughput mode enabled; multi-MessageGroupId strategy documented and implemented; validated in Sprint 9 burst test |
| R6 | Solo developer context switching between app code, IaC, and ops | High | Medium | Strict sprint focus per epic; Claude generates boilerplate IaC and code scaffolds; developer focuses on integration, configuration, and testing |
| R7 | Solace broker customer-side connectivity issues (IP whitelist, port, auth) | Medium | High | Validate connectivity in Sprint 3 using local Solace container first; document all NAT Gateway EIPs and share with customer Solace ops team before Sprint 3 |
| R8 | KEDA CloudWatch scaler requires specific IAM permissions not in standard IRSA policy | Low | Low | Document KEDA IRSA policy requirements in Sprint 7; test scaler trigger in isolated namespace first |

---

## 8. Technology Stack Summary

| Layer | Technology | Version |
|---|---|---|
| Language | Java | 17.0.18 LTS |
| Framework | Spring Boot | 3.5.x |
| Messaging client | Solace Spring Boot Starter (JCSMP) | Starter 5.2.0, JCSMP 10.21+ |
| Build tool | Maven | 3.9.14 |
| Container base | Red Hat UBI 9 + Eclipse Temurin JRE 17 | Latest quarterly patch |
| Container platform | ROSA (OpenShift 4.18+, Kubernetes 1.31+) | 4.18+ |
| IaC — Terraform | Terraform | 1.14.7 |
| IaC — Helm | Helm | 4.1.3 |
| CI/CD | AWS CodePipeline + CodeBuild | N/A (managed) |
| Database | Amazon RDS for PostgreSQL | 15.17 minimum (17.9 preferred) |
| DB migrations | Flyway | 11.x (via Spring Boot 3.5 BOM) |
| Connection pool | HikariCP | BOM-managed (6.x via SB 3.5) |
| Resilience | Resilience4j | 2.4.0 |
| Messaging | SNS FIFO + SQS FIFO | N/A (managed) |
| Secrets | AWS Secrets Manager + External Secrets Operator | ESO 2.2.0 |
| Observability | ADOT Collector + CloudWatch + X-Ray | N/A (managed) |
| Tracing | OpenTelemetry Java SDK + Agent | SDK 1.60.x, Agent 2.26.0 |
| Local dev AWS | LocalStack | 4.14 / 2026.03.x |
| Local dev broker | Solace PubSub+ Standard (Docker) | Latest |
| Load testing | SDKPerf (Solace) + JMeter | N/A |
| Testing | JUnit 5.14.x + Mockito 5.22.x + Testcontainers 2.0.4 | BOM-managed |

---

## 9. Local Development Architecture

```
docker compose up

┌─────────────────────────────────────────────┐
│  Docker Compose (local-dev)                 │
│                                             │
│  ┌─────────────────┐  ┌──────────────────┐  │
│  │ Solace PubSub+  │  │   PostgreSQL 15  │  │
│  │ Standard        │  │   (audit+outbox) │  │
│  │ Port: 55443     │  │   Port: 5432     │  │
│  │ (self-signed    │  └──────────────────┘  │
│  │  mTLS certs)    │                        │
│  └─────────────────┘  ┌──────────────────┐  │
│                        │   LocalStack     │  │
│  ┌─────────────────┐  │   SNS FIFO       │  │
│  │ Spring Boot App │  │   SQS FIFO       │  │
│  │ Profile: local  │  │   S3             │  │
│  │ Port: 8080/8081 │  │   Secrets Mgr    │  │
│  └─────────────────┘  │   SSM            │  │
│                        │   Port: 4566     │  │
│                        └──────────────────┘  │
└─────────────────────────────────────────────┘

Test publisher: SDKPerf or custom Spring Boot test app
Test cert generator: keytool / openssl scripts (in /local-dev/certs/)
```

**Key local dev files (to be created):**
- `local-dev/docker-compose.yml`
- `local-dev/certs/generate-certs.sh` (generates self-signed CA + client cert for JCSMP mTLS)
- `local-dev/solace-init/` (Solace SEMPv2 provisioning scripts for local queue setup)
- `local-dev/localstack-init/` (LocalStack init scripts for SNS/SQS/S3 bootstrap)
- `src/main/resources/application-local.yml` (local Spring profile)

---

## 10. Artefacts Produced by This Project

| Artefact | File / Location | Purpose |
|---|---|---|
| **Project Plan** (this document) | `project-plan.md` | Sprint roadmap, epics, dependencies, risks |
| **Backlog** | `backlog.md` | All user stories with acceptance criteria, story points, sprint assignment |
| **Local Dev Environment** | `local-dev/` | Docker Compose, cert scripts, init scripts |
| **Terraform Modules** | `infra/terraform/` | All AWS infrastructure, parameterised, environment-aware |
| **Helm Chart** | `helm/hermes/` | Complete application deployment chart |
| **Spring Boot Application** | `src/` | Full application source code |
| **Flyway Migrations** | `src/main/resources/db/migration/` | DB schema versioned migrations |
| **CI/CD Pipeline Definition** | `cicd/` | CodePipeline + CodeBuild definitions |
| **Load Test Scripts** | `load-tests/` | JMeter plans + SDKPerf scripts |
| **DR Runbook** | `docs/runbooks/` | Operational procedures for all failure scenarios |
| **Architecture Decision Records** | `docs/adr/` | Key decisions (mTLS, outbox, JCSMP, RDS Proxy rationale) |
| **CloudWatch Dashboards** | `infra/terraform/modules/monitoring/` | Dashboard JSON definitions |
