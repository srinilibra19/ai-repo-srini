# CLAUDE.md — Containers with Middleware

This file governs how Claude assists in building this project. All code, infrastructure, and configuration produced must follow these standards without exception.

---

## Project Overview

**Containers with Middleware** is a production-grade, resilient Solace-to-AWS messaging bridge.

- Subscribes to a **customer-managed Solace PubSub+ broker** via JCSMP over mTLS
- Processes messages with **transactional integrity** (audit + outbox in one PostgreSQL TX)
- Fans out to **AWS SNS FIFO → SQS FIFO** for downstream consumers
- Runs on **ROSA (Red Hat OpenShift on AWS)** as independently-scalable per-destination Deployments
- MVP destination: `flightschedules`

**Message flow:**
```
Solace → JCSMP FlowReceiver → RDS (audit + outbox, 1 TX) → ACK → Outbox Poller → SNS FIFO → SQS FIFO
```

---

## Repository Folder Structure

```
containers-with-middleware/
│
├── CLAUDE.md                          # This file
├── README.md                          # Project overview and quickstart
├── project-plan.md                    # Sprint roadmap and epics
├── backlog.md                         # User stories and acceptance criteria
├── requirements.md                    # Detailed requirements specification
│
├── local-dev/                         # Sprint 1 — Local development environment
│   ├── docker-compose.yml             # Solace + PostgreSQL + LocalStack
│   ├── .env.example                   # Template for local env vars (never commit .env)
│   ├── certs/
│   │   ├── generate-certs.sh          # Generates self-signed CA + client cert (PKCS12)
│   │   ├── .gitignore                 # Ignores generated cert files
│   ├── solace-init/
│   │   └── provision-queues.sh        # SEMPv2 scripts to create local queues/subscriptions
│   └── localstack-init/
│       └── bootstrap.sh               # Creates SNS FIFO, SQS FIFO, S3, SSM params locally
│
├── src/                               # Spring Boot application source
│   ├── main/
│   │   ├── java/com/middleware/hermes/
│   │   │   ├── HermesApplication.java
│   │   │   ├── config/
│   │   │   │   ├── SolaceConfig.java           # JCSMP session factory, FlowReceiver setup
│   │   │   │   ├── AwsConfig.java              # SNS/SQS/S3 SDK client beans
│   │   │   │   ├── DataSourceConfig.java        # HikariCP config
│   │   │   │   └── ResilienceConfig.java        # Resilience4j circuit breaker/retry beans
│   │   │   ├── messaging/
│   │   │   │   ├── SolaceMessageConsumer.java   # JCSMP FlowReceiver, XMLMessageListener
│   │   │   │   ├── SolaceSessionEventHandler.java
│   │   │   │   ├── OutboxPoller.java            # SKIP LOCKED poller → SNS publisher
│   │   │   │   └── SnsPublisher.java            # Async SNS FIFO publish with dedup ID
│   │   │   ├── processing/
│   │   │   │   ├── MessageProcessor.java        # Orchestrates: validate → audit → outbox → ack
│   │   │   │   ├── IdempotencyChecker.java      # Duplicate detection via audit table
│   │   │   │   └── ClaimCheckHandler.java       # S3 upload for messages > 200 KB
│   │   │   ├── model/
│   │   │   │   ├── canonical/
│   │   │   │   │   └── FlightScheduleMessage.java   # Canonical POJO/DTO per destination
│   │   │   │   ├── entity/
│   │   │   │   │   ├── AuditMessage.java
│   │   │   │   │   └── OutboxMessage.java
│   │   │   │   └── OutboxStatus.java            # Enum: PENDING, PUBLISHED, DLQ, FAILED
│   │   │   ├── repository/
│   │   │   │   ├── AuditMessageRepository.java
│   │   │   │   └── OutboxMessageRepository.java
│   │   │   ├── health/
│   │   │   │   └── SolaceHealthIndicator.java   # Spring Actuator health contributor
│   │   │   ├── metrics/
│   │   │   │   └── HermesMetrics.java           # Micrometer custom metric definitions
│   │   │   └── exception/
│   │   │       ├── MessageValidationException.java
│   │   │       ├── DuplicateMessageException.java
│   │   │       └── OutboxPublishException.java
│   │   └── resources/
│   │       ├── application.yml                  # Base config (no secrets, no env-specific values)
│   │       ├── application-local.yml            # Local Docker Compose profile
│   │       ├── application-aws.yml              # ROSA/AWS profile (reads from K8s env vars)
│   │       └── db/
│   │           └── migration/
│   │               ├── V1__create_audit_messages.sql
│   │               ├── V2__create_outbox_messages.sql
│   │               ├── V3__create_notify_trigger.sql
│   │               └── V4__create_indexes.sql
│   └── test/
│       ├── java/com/middleware/hermes/
│       │   ├── unit/
│       │   │   ├── processing/
│       │   │   │   ├── MessageProcessorTest.java
│       │   │   │   └── IdempotencyCheckerTest.java
│       │   │   └── messaging/
│       │   │       └── OutboxPollerTest.java
│       │   ├── integration/
│       │   │   ├── SolaceIntegrationTest.java   # Testcontainers: Solace container
│       │   │   ├── OutboxToSnsTest.java          # Testcontainers: PostgreSQL + LocalStack
│       │   │   └── ClaimCheckIntegrationTest.java
│       │   └── contract/
│       │       └── FlightScheduleMessageContractTest.java  # Schema validation tests
│       └── resources/
│           ├── application-test.yml
│           └── test-data/
│               └── flightschedule-sample.json
│
├── infra/
│   └── terraform/
│       ├── environments/
│       │   ├── staging/
│       │   │   ├── main.tf
│       │   │   ├── variables.tf
│       │   │   └── terraform.tfvars
│       │   └── prod/
│       │       ├── main.tf
│       │       ├── variables.tf
│       │       └── terraform.tfvars
│       ├── modules/
│       │   ├── vpc/                   # VPC, subnets, NAT GW, IGW, route tables
│       │   ├── rosa/                  # ROSA cluster, machine pools, OIDC
│       │   ├── ecr/                   # ECR repository + lifecycle policy
│       │   ├── kms/                   # KMS CMKs for RDS, SNS, SQS, S3, Secrets Manager
│       │   ├── rds/                   # RDS PostgreSQL Multi-AZ + parameter groups
│       │   ├── rds-proxy/             # RDS Proxy (always enabled)
│       │   ├── secrets/               # Secrets Manager secrets (Solace creds, certs)
│       │   ├── sns-sqs/               # SNS FIFO + SQS FIFO + DLQ per destination
│       │   ├── s3/                    # S3 buckets: claim-check payloads, logs, state
│       │   ├── vpc-endpoints/         # Interface + Gateway VPC endpoints
│       │   ├── iam/                   # IRSA roles, pod policies, CodeBuild role
│       │   ├── eso/                   # External Secrets Operator Terraform module
│       │   └── monitoring/            # CloudWatch log groups, dashboards, alarms
│       └── backend.tf                 # S3 + DynamoDB remote state config
│
├── helm/
│   └── hermes/
│       ├── Chart.yaml
│       ├── values.yaml                # Defaults only (no secrets, no env-specific values)
│       ├── values-local.yaml
│       ├── values-staging.yaml
│       └── values-prod.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── configmap.yaml
│           ├── externalsecret.yaml    # ESO ExternalSecret CRD
│           ├── serviceaccount.yaml    # IRSA-annotated ServiceAccount
│           ├── hpa.yaml
│           ├── keda-scaledobject.yaml
│           ├── pdb.yaml               # Pod Disruption Budget
│           ├── networkpolicy.yaml
│           └── _helpers.tpl
│
├── cicd/
│   ├── buildspec-build.yml            # CodeBuild: Maven build + unit tests
│   ├── buildspec-scan.yml             # CodeBuild: Trivy + Snyk security scan
│   ├── buildspec-docker.yml           # CodeBuild: Docker multi-stage build + ECR push
│   ├── buildspec-integration.yml      # CodeBuild: Testcontainers integration tests
│   ├── buildspec-deploy-staging.yml   # CodeBuild: helm upgrade staging
│   ├── buildspec-deploy-prod.yml      # CodeBuild: helm upgrade prod
│   └── pipeline.tf                   # CodePipeline definition (Terraform)
│
├── load-tests/
│   ├── sdkperf/
│   │   ├── baseline.sh               # 1,000 msg/s for 1 hour
│   │   ├── burst.sh                  # 3,000 msg/s for 15 min
│   │   └── reconnection.sh           # Kill Solace mid-load test
│   └── jmeter/
│       └── hermes-actuator.jmx        # JMeter plan for HTTP health/metrics endpoints
│
└── docs/
    ├── adr/
    │   ├── 001-jcsmp-over-jms.md
    │   ├── 002-transactional-outbox.md
    │   ├── 003-rosa-over-ecs.md
    │   ├── 004-rds-proxy-always-on.md
    │   └── 005-individual-ack-mode.md
    └── runbooks/
        ├── solace-disconnect-recovery.md
        ├── rds-failover-recovery.md
        ├── certificate-rotation.md
        ├── destination-onboarding.md
        └── cloudwatch-logs-insights.md
```

---

## Technology Stack

| Layer | Technology | Version |
|---|---|---|
| Language | Java | 17 |
| Framework | Spring Boot | 3.x |
| Messaging client | Solace Spring Boot Starter (JCSMP) | 10.21+ |
| Build | Maven | 3.9+ |
| Container base | Red Hat UBI 9 + Eclipse Temurin JRE 17 | Latest |
| Container platform | ROSA (OpenShift 4.14+, Kubernetes 1.27+) | 4.14+ |
| IaC | Terraform + Helm | TF 1.7+, Helm 3.x |
| CI/CD | AWS CodePipeline + CodeBuild | Managed |
| Database | Amazon RDS for PostgreSQL | 15+ |
| DB migrations | Flyway | 9.x |
| Connection pool | HikariCP | Spring Boot default |
| Resilience | Resilience4j | 2.x |
| Messaging | SNS FIFO + SQS FIFO | Managed |
| Secrets | AWS Secrets Manager + External Secrets Operator | ESO 0.9+ |
| Observability | ADOT Collector + CloudWatch + X-Ray | Managed |
| Tracing | OpenTelemetry SDK | 1.x |
| Local AWS | LocalStack | 3.x |
| Local broker | Solace PubSub+ Standard (Docker) | Latest |
| Testing | JUnit 5 + Mockito + Testcontainers | Latest |

---

## Coding Standards

### Java / Spring Boot

- Java 17. Use records for immutable DTOs, sealed classes where appropriate, text blocks for SQL.
- All public service methods must have `@Transactional` boundaries explicitly declared — never rely on implicit transactions.
- No `@Autowired` field injection. Use constructor injection only.
- Never catch and swallow exceptions silently. Always log with correlation context before rethrowing or routing to DLQ.
- All new classes must have a corresponding unit test. Integration tests via Testcontainers, not mocks, for DB and messaging.
- Structured JSON logging only (Logback JSON encoder). Every log line must include: `correlationId`, `messageId`, `destination`. Never use `System.out`.
- Use `@Slf4j` (Lombok) for logging. Log at `DEBUG` for message lifecycle, `INFO` for state transitions, `WARN` for recoverable errors, `ERROR` for failures requiring attention.
- Do not hardcode any configuration values. All config goes in `application.yml` or environment-specific overlays.
- Secrets never appear in config files, logs, or stack traces. Use placeholder references to K8s Secrets only.

### Solace / JCSMP

- Always use `INDIVIDUAL_ACKNOWLEDGE` mode — never `CLIENT_ACK` or auto-ack.
- ACK a message **only** after the DB transaction has committed successfully. Never before.
- FlowReceiver must be stopped (backpressure) when circuit breaker opens. Must be restarted when circuit breaker closes.
- `reconnectRetries` must always be `-1` (infinite). Never set a finite value in production config.
- Client name must include the pod UID (`aws-hermes-{destination}-{pod-uid}`) to prevent name collisions during rolling updates.
- Prefetch (`sub-ack-window-size`) must be `32`. Do not increase without load testing validation.

### Transactional Outbox

- Audit write and outbox write must always be in a **single `@Transactional` method** — never split across two transactions.
- Outbox poller must use `SELECT ... FOR UPDATE SKIP LOCKED` to support competing consumers safely.
- LISTEN/NOTIFY is the primary trigger for the outbox poller. The 500ms fallback poll is mandatory and must always be present.
- Outbox status transitions: `PENDING` → `PUBLISHED` (success) or `FAILED` → `DLQ` (after retries exhausted).

### Resilience

- Circuit breakers required on: RDS writes, SNS publishes.
- Retry with exponential backoff + jitter required on: SNS publish, S3 upload.
- Bulkhead (separate thread pools) required for: Solace consumption, RDS writes, SNS publishes.
- Never retry inside a `@Transactional` boundary. Retry must wrap the transaction, not be inside it.

---

## Infrastructure Standards

### Terraform

- Every resource must have tags: `Project`, `Environment`, `Owner`, `CostCenter`, `Destination`.
- All modules must be parameterised. No hardcoded ARNs, account IDs, or region strings inside modules.
- Remote state is mandatory. Never use local state. Backend: S3 + DynamoDB lock.
- Always run `terraform plan` and review before `terraform apply`. Never apply blindly.
- RDS Proxy is always enabled (`enable_rds_proxy = true`). This is not optional.
- KMS CMKs required for: RDS, SNS, SQS, S3, Secrets Manager. No AWS-managed keys in production.
- VPC Endpoints required for all AWS service access from ROSA pods (SNS, SQS, Secrets Manager, SSM, CloudWatch, X-Ray, KMS, ECR, S3).

### Helm

- No secrets in `values.yaml` or any values file. All secrets come from `ExternalSecret` CRDs.
- Every Deployment must have: `livenessProbe`, `readinessProbe`, `startupProbe`, resource `requests` and `limits`, `podAntiAffinity` across AZs, `PodDisruptionBudget`.
- `terminationGracePeriodSeconds` must be `60` to allow graceful Solace disconnect + outbox flush.
- Image tags must be explicit SHAs in production. Never use `latest`.

---

## Security Standards

- No credentials, secrets, certificates, or keys in Git — ever. Verified via `.gitignore` and pre-commit hooks.
- Java truststore and keystore mounted as K8s Secret volumes (synced from Secrets Manager via ESO). Never baked into images.
- All inter-service communication within AWS uses VPC Endpoints. No traffic via public internet for AWS services.
- IRSA (IAM Roles for Service Accounts) for all pod-level AWS access. No EC2 instance profile fallback.
- NetworkPolicies must restrict pod ingress/egress to only required sources and destinations.
- SCCs (Security Context Constraints) must be applied. Pods must not run as root.
- Certificate expiry CloudWatch Alarms required at 30, 14, and 7 days.

---

## Observability Standards

- All CloudWatch metrics go in the `CustomerMiddleware` namespace with dimensions: `Destination`, `Environment`.
- Required custom metrics per destination: `solace.messages.received`, `solace.messages.processed`, `solace.messages.failed`, `solace.connection.status`, `audit.insert.latency`, `sns.publish.latency`, `outbox.pending.count`, `processing.e2e.latency`.
- Every new failure mode introduced in a story must have a corresponding CloudWatch Alarm.
- X-Ray custom spans required for: Solace receive, RDS transaction, SNS publish.
- Log group naming: `hermes/{destination}/{environment}` with 90-day retention.

---

## Testing Standards

- Unit test coverage: minimum 80% for all new code.
- Integration tests use **Testcontainers** (real Solace container, real PostgreSQL). No mocked DB or broker in integration tests.
- Every story must have: at least one happy-path test and at least one failure-path test.
- Idempotency must be tested explicitly: publish the same message ID twice, confirm only one audit record.
- DLQ routing must be tested: simulate 3 consecutive failures, confirm message reaches DLQ and audit status is `DLQ`.
- Load tests (Sprint 9) must meet: P95 < 500ms at 1,000 msg/s, P99 < 2s at 3,000 msg/s burst, zero message loss.

---

## Git Workflow

- Branch naming: `feature/{epic-id}-{short-description}` (e.g., `feature/E5-solace-session-manager`)
- Commit messages: imperative mood, reference story ID (e.g., `Add JCSMP FlowReceiver with INDIVIDUAL_ACK [E5-S2]`)
- PRs require: passing CI pipeline (build + unit tests + Trivy scan), self-review checklist completed.
- Never commit directly to `main`. All changes via PR.
- Never skip pre-commit hooks (`--no-verify`). Fix the underlying issue.

---

## Definition of Done

A story is done only when ALL of the following are true:

- [ ] Code reviewed (self-review checklist + Claude review)
- [ ] Unit tests written and passing (>80% coverage for new code)
- [ ] Integration test covers happy path and at least one failure path
- [ ] No new high/critical CVEs (Trivy/Snyk clean)
- [ ] Structured logging added with `correlationId`, `messageId`, `destination`
- [ ] CloudWatch metric/alarm added if the story introduces a new failure mode
- [ ] Terraform/Helm changes committed and `terraform plan` is clean
- [ ] `docker compose up` local stack still works after the change
- [ ] Acceptance criteria verified manually or by automated test
- [ ] No secrets in code, config files, or logs

---

## Local Dev Quick Reference

```bash
# Start full local stack
cd local-dev
docker compose up -d

# Generate local mTLS certs
./local-dev/certs/generate-certs.sh

# Run app locally
./mvnw spring-boot:run -Dspring-boot.run.profiles=local

# Run unit tests
./mvnw test

# Run integration tests (requires Docker)
./mvnw verify -P integration-tests

# Terraform plan (staging)
cd infra/terraform/environments/staging
terraform init && terraform plan

# Helm dry-run
helm upgrade --install hermes-flightschedules ./helm/hermes \
  -f helm/hermes/values-staging.yaml \
  --dry-run --debug
```

---

## Key Architectural Decisions

See `docs/adr/` for full rationale. Summary:

| Decision | Choice | Reason |
|---|---|---|
| Messaging client | JCSMP (not JMS, not Binder) | Full control over per-message ACK timing required by outbox pattern |
| ACK mode | `INDIVIDUAL_ACKNOWLEDGE` | Prevents silent message loss on pod crash with concurrent processing |
| Reconnection | `reconnectRetries: -1` (infinite, fixed 3s interval) | Production tolerance for transient WAN disruptions |
| Outbox trigger | LISTEN/NOTIFY + 500ms fallback | Near-real-time without polling overhead; fallback ensures no stuck records |
| RDS Proxy | Always enabled | Connection pooling for HPA/KEDA scale-out; RDS connection limits |
| Auth | mTLS (preferred) → OAuth → Basic+TLS | Security posture; depends on Solace broker capabilities |
| Container platform | ROSA | Enterprise OpenShift + AWS-native observability + IRSA |
