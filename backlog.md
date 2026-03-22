# Containers with Middleware — Product Backlog
## MVP: flightschedules destination

| Field | Value |
|---|---|
| **Version** | 1.0 |
| **Date** | 2026-03-19 |
| **Story Point Scale** | 1=2hrs, 2=4hrs, 3=1day, 5=2days, 8=3-4days, 13=1week |
| **Sprint Capacity** | ~35 points (solo developer, 2-week sprint) |

---

## Estimation Key
- **SP** = Story Points
- **Deps** = Depends on
- **AC** = Acceptance Criteria

---

## Epic E0: Local Development Environment
**Goal:** Developer can run the full Containers with Middleware stack locally (Solace, PostgreSQL, LocalStack, Spring Boot app) without any AWS access. This enables fast local iteration before any AWS infrastructure exists.

---

### US-E0-001: Docker Compose stack for local development
**As a** developer, **I want** a Docker Compose file that starts Solace PubSub+ Standard, PostgreSQL, and LocalStack together, **so that** I can develop and test the full message flow locally without AWS credentials.

**SP:** 5 | **Sprint:** 1 | **Deps:** None

**AC:**
- [ ] `docker compose up` starts: Solace PubSub+ Standard (ports 55555, 55443, 8080), PostgreSQL 15 (port 5432), LocalStack (port 4566)
- [ ] All services have health checks defined
- [ ] Solace admin UI accessible at `http://localhost:8080` (admin/admin)
- [ ] PostgreSQL accessible at `localhost:5432` with `hermes`/`hermes` credentials
- [ ] LocalStack SNS/SQS/S3/SecretsManager/SSM services available
- [ ] `docker compose down -v` cleanly removes volumes
- [ ] README documents how to start the local stack

---

### US-E0-002: Self-signed mTLS certificate generation for local Solace
**As a** developer, **I want** a script that generates a self-signed CA and client certificate pair in PKCS12 format compatible with JCSMP, **so that** I can test mTLS authentication locally before using real certificates.

**SP:** 3 | **Sprint:** 1 | **Deps:** US-E0-001

**AC:**
- [ ] Script `local-dev/certs/generate-certs.sh` generates:
  - Self-signed CA certificate (`ca.crt`)
  - Server certificate signed by CA (`server.crt`, `server.key`)
  - Client certificate signed by CA (`client.crt`, `client.key`)
  - Client keystore as PKCS12 (`client-keystore.p12`) with configurable password
  - Truststore as JKS (`truststore.jks`) containing the CA cert
- [ ] Solace Docker container configured with server cert and CA via init script
- [ ] JCSMP can connect to local Solace using the generated client keystore + truststore
- [ ] Script is idempotent (re-running it regenerates certs without manual cleanup)
- [ ] Certificate passwords are stored in a local `.env` file excluded from Git

---

### US-E0-003: LocalStack initialisation for SNS FIFO and SQS FIFO
**As a** developer, **I want** LocalStack to be pre-configured with the SNS FIFO topic and SQS FIFO queues matching the production topology, **so that** the full message flow from Solace to SQS works locally.

**SP:** 3 | **Sprint:** 1 | **Deps:** US-E0-001

**AC:**
- [ ] LocalStack init script creates: `hermes-flightschedules.fifo` SNS FIFO topic; `hermes-flightschedules-consumer-a.fifo` SQS FIFO queue; `hermes-flightschedules-dlq.fifo` SQS DLQ FIFO queue
- [ ] SNS subscription from topic to SQS queue is configured
- [ ] S3 bucket `hermes-claim-check-local` is created for large message payloads
- [ ] LocalStack Secrets Manager contains test Solace credentials and cert paths
- [ ] Init script runs automatically on `docker compose up` (via init container or healthcheck dependency)

---

### US-E0-004: Solace local queue and subscription provisioning
**As a** developer, **I want** the local Solace broker to be provisioned with a `hermes.flightschedules` queue and `flightschedules/>` topic subscription, **so that** I can publish test messages that are picked up by the consumer application.

**SP:** 2 | **Sprint:** 1 | **Deps:** US-E0-001

**AC:**
- [ ] SEMPv2 init script provisions: queue `hermes.flightschedules` (non-exclusive, 4GB spool), topic subscription `flightschedules/>`, DMQ `hermes.flightschedules.dmq`
- [ ] Init script runs on Solace container startup
- [ ] SDKPerf command documented in README to publish 10 test messages to `flightschedules/events`
- [ ] Test publisher can publish messages of variable size (including >200 KB)

---

### US-E0-005: Spring Boot local application profile
**As a** developer, **I want** a `local` Spring profile that points to Docker Compose services instead of AWS, **so that** I can run the Spring Boot app locally with `./mvnw spring-boot:run -Dspring-boot.run.profiles=local`.

**SP:** 2 | **Sprint:** 1 | **Deps:** US-E0-001, US-E0-002, US-E0-003

**AC:**
- [ ] `application-local.yml` configures Solace host as `tcps://localhost:55443`
- [ ] Keystore and truststore paths point to `local-dev/certs/` files
- [ ] DataSource URL points to `localhost:5432`
- [ ] SNS and SQS endpoint URLs point to `http://localhost:4566`
- [ ] AWS credentials for LocalStack use static test credentials (`test`/`test`)
- [ ] App starts successfully with `local` profile and logs `Solace session connected`

---

## Epic E1: AWS Foundation Infrastructure (Terraform)
**Goal:** All base AWS infrastructure is provisioned as code. Terraform state is remote and locked. VPC, ROSA, ECR, KMS, and S3 are ready.

---

### US-E1-001: Terraform remote state backend
**As a** developer, **I want** Terraform state stored in S3 with DynamoDB locking, **so that** state is durable, version-controlled, and protected from concurrent modifications.

**SP:** 2 | **Sprint:** 1 | **Deps:** None

**AC:**
- [ ] S3 bucket `hermes-terraform-state-{account-id}` with versioning, encryption (KMS), and public access blocked
- [ ] DynamoDB table `hermes-terraform-locks` for state locking
- [ ] `backend.tf` configured to use S3 backend
- [ ] Bootstrap script `infra/terraform/bootstrap/` provisions the state bucket and lock table using local state initially, then migrates
- [ ] Separate state per environment (`dev`, `staging`, `prod`) using workspaces or separate state keys

---

### US-E1-002: VPC and networking module
**As a** developer, **I want** a Terraform VPC module that creates private subnets, NAT Gateways, and an Internet Gateway, **so that** ROSA worker nodes are in private subnets with outbound connectivity to the Solace broker via NAT.

**SP:** 5 | **Sprint:** 1 | **Deps:** US-E1-001

**AC:**
- [ ] VPC with CIDR `10.0.0.0/16` (configurable)
- [ ] Private subnets in 2 AZs (e.g., `10.0.1.0/24`, `10.0.2.0/24`)
- [ ] Public subnets in 2 AZs for NAT Gateways (e.g., `10.0.101.0/24`, `10.0.102.0/24`)
- [ ] One NAT Gateway per AZ with Elastic IP (both EIPs output from Terraform for sharing with customer Solace ops team)
- [ ] Internet Gateway attached to VPC
- [ ] Route tables: private subnets route `0.0.0.0/0` via NAT Gateway (same-AZ); public subnets route `0.0.0.0/0` via IGW
- [ ] VPC Flow Logs enabled, stored in S3 with 90-day lifecycle policy
- [ ] Route 53 Resolver Query Logging enabled
- [ ] All subnets tagged with required tags

---

### US-E1-003: VPC Interface Endpoints
**As a** developer, **I want** VPC PrivateLink endpoints for all AWS services used by the application, **so that** AWS API traffic stays within the AWS network and does not incur NAT Gateway data processing charges.

**SP:** 5 | **Sprint:** 2 | **Deps:** US-E1-002

**AC:**
- [ ] S3 Gateway endpoint (free)
- [ ] Interface endpoints for: SNS, SQS, Secrets Manager, SSM, CloudWatch (`monitoring`), CloudWatch Logs, X-Ray, KMS, ECR API, ECR DKR, STS
- [ ] Each interface endpoint has a Security Group allowing HTTPS (443) from ROSA worker node Security Group
- [ ] Endpoint policies follow least privilege (restrict to account resources only)
- [ ] DNS resolution enabled for all interface endpoints (private DNS names)
- [ ] `terraform plan` shows no unnecessary endpoint recreation on re-apply

---

### US-E1-004: KMS Customer Managed Keys
**As a** developer, **I want** KMS CMKs for each data store and service, **so that** encryption at rest is under our key management control.

**SP:** 3 | **Sprint:** 2 | **Deps:** US-E1-001

**AC:**
- [ ] CMK for RDS (`hermes-rds-key`)
- [ ] CMK for SNS FIFO topics (`hermes-sns-key`)
- [ ] CMK for SQS FIFO queues (`hermes-sqs-key`)
- [ ] CMK for S3 buckets (`hermes-s3-key`)
- [ ] CMK for Secrets Manager (`hermes-secrets-key`)
- [ ] Key policies enforce: key administrators ≠ key users (separation of duties)
- [ ] Key rotation enabled on all CMKs
- [ ] Key ARNs output from Terraform for use in dependent modules

---

### US-E1-005: ROSA cluster provisioning
**As a** developer, **I want** a ROSA cluster provisioned via Terraform using the `rhcs` provider, **so that** the OpenShift cluster is reproducible, version-controlled, and environment-aware.

**SP:** 8 | **Sprint:** 2 | **Deps:** US-E1-002, US-E1-003

**AC:**
- [ ] ROSA cluster with STS enabled, OpenShift 4.14+
- [ ] Worker machine pool: `m6i.xlarge` (prod), `m6i.large` (non-prod), min 3 nodes across 2 AZs, max 12
- [ ] Cluster in private subnets; cluster API server private (PrivateLink)
- [ ] Cluster Autoscaler enabled (min 3, max 12)
- [ ] ECR image pull secret configured in `hermes` namespace
- [ ] ADOT Operator, KEDA Operator, ESO Operator installed via OperatorHub/OLM after cluster creation
- [ ] `oc login` command documented in README post-provisioning

---

### US-E1-006: ECR repository and image scanning
**As a** developer, **I want** an ECR repository for the hermes application image, **so that** container images are stored securely with vulnerability scanning.

**SP:** 2 | **Sprint:** 1 | **Deps:** US-E1-001

**AC:**
- [ ] ECR repository `hermes/consumer` created
- [ ] Image scanning on push enabled
- [ ] Lifecycle policy: keep last 10 tagged images; delete untagged images after 1 day
- [ ] ECR replication to DR region disabled (cross-region DR out of scope)
- [ ] IAM policy allowing ROSA IRSA role to pull images

---

### US-E1-007: S3 buckets for logs and archives
**As a** developer, **I want** S3 buckets for application archives, claim-check payloads, and operational logs, **so that** data retention policies are enforced and cold data is cost-effective.

**SP:** 3 | **Sprint:** 1 | **Deps:** US-E1-004

**AC:**
- [ ] Bucket `hermes-audit-archive-{env}`: encryption (KMS CMK), versioning enabled, block public access, lifecycle: transition to Glacier after 90 days, delete after 365 days
- [ ] Bucket `hermes-claim-check-{env}`: encryption (KMS CMK), block public access, lifecycle: delete after 90 days
- [ ] Bucket `hermes-logs-{env}`: encryption (KMS CMK), block public access, lifecycle: delete after 90 days (VPC flow logs, CloudTrail)
- [ ] All buckets tagged with standard tags

---

## Epic E2: Security Baseline
**Goal:** All secrets, certificates, and identities are managed. OpenShift namespace is locked down with SCCs, NetworkPolicies, and RBAC.

---

### US-E2-001: Secrets Manager secrets for Solace credentials and certificates
**As a** developer, **I want** Solace credentials and TLS certificate material stored in AWS Secrets Manager, **so that** no credentials are baked into container images or committed to Git.

**SP:** 3 | **Sprint:** 2 | **Deps:** US-E1-004

**AC:**
- [ ] Secret `hermes/solace/credentials`: `{ "username": "hermes-aws-consumer", "password": "..." }`
- [ ] Secret `hermes/solace/client-keystore`: base64-encoded PKCS12 keystore (client certificate + key)
- [ ] Secret `hermes/solace/truststore`: base64-encoded JKS truststore (Solace broker CA certificate)
- [ ] Secret `hermes/solace/keystore-password`: keystore password string
- [ ] Secret `hermes/semp/credentials`: SEMP read-only user credentials (separate from client)
- [ ] All secrets encrypted with `hermes-secrets-key` KMS CMK
- [ ] 90-day rotation policy configured (manual rotation for certificates; documented procedure)
- [ ] CloudWatch alarm for certificate expiry (30, 14, 7 days before) via Lambda rotation notification

---

### US-E2-002: IAM roles and IRSA configuration
**As a** developer, **I want** IRSA-annotated Kubernetes ServiceAccounts with least-privilege IAM roles, **so that** pods can access AWS services without long-term credentials.

**SP:** 5 | **Sprint:** 2 | **Deps:** US-E1-005

**AC:**
- [ ] IAM role `hermes-flightschedules-role` with trust policy for IRSA (OIDC provider from ROSA cluster)
- [ ] Policy for SNS FIFO publish: `sns:Publish`, `sns:PublishBatch` on `hermes-flightschedules.fifo` ARN only
- [ ] Policy for Secrets Manager read: `secretsmanager:GetSecretValue` on `hermes/solace/*` and `hermes/db/*` ARNs only
- [ ] Policy for KMS: `kms:Decrypt`, `kms:GenerateDataKey` on relevant CMK ARNs
- [ ] Policy for CloudWatch: `cloudwatch:PutMetricData` on `CustomerMiddleware` namespace only
- [ ] Policy for X-Ray: `xray:PutTraceSegments`, `xray:PutTelemetryRecords`
- [ ] Policy for S3 claim-check: `s3:PutObject`, `s3:GetObject` on `hermes-claim-check-{env}/*` only
- [ ] Kubernetes ServiceAccount `hermes-flightschedules-sa` annotated with IAM role ARN
- [ ] ADOT Collector ServiceAccount with separate IAM role (CloudWatch + X-Ray + CloudWatch Logs write)
- [ ] No `*` resources or `*` actions in any policy

---

### US-E2-003: External Secrets Operator configuration
**As a** developer, **I want** ESO configured with a ClusterSecretStore pointing to AWS Secrets Manager, **so that** Kubernetes Secrets are automatically synced from Secrets Manager.

**SP:** 3 | **Sprint:** 2 | **Deps:** US-E2-001, US-E2-002

**AC:**
- [ ] ESO installed via OperatorHub on ROSA cluster
- [ ] `ClusterSecretStore` configured using IRSA (ROSA OIDC) for authentication
- [ ] `ExternalSecret` for Solace credentials syncs to K8s Secret `hermes-solace-credentials`
- [ ] `ExternalSecret` for client keystore syncs to K8s Secret `hermes-solace-keystore` (binary data)
- [ ] `ExternalSecret` for truststore syncs to K8s Secret `hermes-solace-truststore` (binary data)
- [ ] `ExternalSecret` for DB credentials syncs to K8s Secret `hermes-db-credentials`
- [ ] All ExternalSecrets have `refreshInterval: 1h`
- [ ] ESO metrics scraped by ADOT Collector

---

### US-E2-004: OpenShift namespace security (SCCs, RBAC, NetworkPolicies)
**As a** developer, **I want** the `hermes` namespace locked down with OpenShift SCCs, RBAC, and NetworkPolicies, **so that** pods cannot escalate privileges and network traffic is restricted to required paths only.

**SP:** 5 | **Sprint:** 3 | **Deps:** US-E1-005

**AC:**
- [ ] Namespace `hermes` created with labels `pod-security.kubernetes.io/enforce: restricted`
- [ ] ResourceQuota: 40 vCPU, 80Gi memory max (10 pods × 4 vCPU/4Gi = 40 CPU/40Gi with headroom)
- [ ] LimitRange: default request 1 vCPU/2Gi, limit 2 vCPU/4Gi
- [ ] SCC `restricted` applied to ServiceAccount `hermes-flightschedules-sa` — no root, no privileged, drops all capabilities
- [ ] NetworkPolicy `default-deny`: deny all ingress and egress in `hermes` namespace by default
- [ ] NetworkPolicy `allow-solace-egress`: allow egress to Solace broker IP:55443 from hermes pods
- [ ] NetworkPolicy `allow-rds-egress`: allow egress to RDS endpoint:5432
- [ ] NetworkPolicy `allow-vpc-endpoints-egress`: allow egress to VPC endpoint IPs:443
- [ ] NetworkPolicy `allow-actuator-ingress`: allow ingress to port 8081 from monitoring namespace only
- [ ] RBAC Role `hermes-role`: read ConfigMaps and Secrets in `hermes` namespace only
- [ ] RoleBinding: `hermes-flightschedules-sa` → `hermes-role`
- [ ] ImagePolicy: only ECR registry allowed in `hermes` namespace

---

### US-E2-005: RDS Secrets Manager and IAM database auth
**As a** developer, **I want** RDS credentials managed in Secrets Manager with automatic rotation, **so that** database passwords are never hard-coded and rotate every 90 days.

**SP:** 3 | **Sprint:** 3 | **Deps:** US-E2-001

**AC:**
- [ ] Secret `hermes/db/credentials`: `{ "username": "hermes_app", "password": "...", "host": "...", "port": "5432", "dbname": "hermes" }`
- [ ] Secrets Manager native rotation configured for PostgreSQL (Lambda rotation function)
- [ ] 90-day rotation schedule
- [ ] `ExternalSecret` syncs DB credentials to K8s Secret `hermes-db-credentials`
- [ ] DataSource URL in Spring Boot references K8s Secret (not hardcoded)

---

## Epic E3: Data Layer (Amazon RDS)
**Goal:** RDS PostgreSQL Multi-AZ is provisioned with full schema via Flyway migrations. RDS Proxy is in place.

---

### US-E3-001: RDS PostgreSQL Multi-AZ Terraform module
**As a** developer, **I want** RDS PostgreSQL provisioned with Multi-AZ and RDS Proxy via Terraform, **so that** the database is highly available and connection failover is transparent to the application.

**SP:** 5 | **Sprint:** 2 | **Deps:** US-E1-002, US-E1-004

**AC:**
- [ ] RDS instance: PostgreSQL 15+, `db.r6g.large` (prod), `db.t3.medium` (non-prod)
- [ ] Multi-AZ: enabled (automatic standby replica)
- [ ] Storage: gp3, 100 GB initial, autoscaling to 500 GB, provisioned IOPS 3000
- [ ] Encryption at rest: KMS CMK `hermes-rds-key`
- [ ] SSL/TLS enforced: `rds.force_ssl=1` parameter group
- [ ] Automated backups: 35-day retention, point-in-time recovery enabled
- [ ] Maintenance window: Sunday 03:00-04:00 UTC
- [ ] RDS Proxy: enabled, `MaxConnectionsPercent=50` (provides headroom; adjustable)
- [ ] RDS Proxy uses IAM authentication (`aws_db_proxy_auth`)
- [ ] Security Group: allow inbound 5432 from ROSA worker node Security Group only
- [ ] Parameter group: `max_connections=1600`, `shared_buffers=256MB`, `wal_level=logical` (for LISTEN/NOTIFY)
- [ ] CloudWatch Enhanced Monitoring enabled

---

### US-E3-002: Database schema migration — audit_messages table
**As a** developer, **I want** the `audit_messages` table created via a Flyway migration, **so that** every received Solace message has a full audit record with lifecycle status tracking.

**SP:** 3 | **Sprint:** 3 | **Deps:** US-E3-001

**AC:**
- [ ] Flyway migration `V1__create_audit_messages.sql` creates table with all columns specified in REQ-DB-007
- [ ] `UNIQUE` constraint on `message_id`
- [ ] Indexes: `message_id` (unique), `status`, `created_at`, `source_destination`, `correlation_id`
- [ ] Default values: `status='RECEIVED'`, `retry_count=0`, `created_at=NOW()`, `updated_at=NOW()`
- [ ] Trigger `update_audit_messages_updated_at` updates `updated_at` on every row update
- [ ] Migration runs automatically on application startup via Spring Boot Flyway auto-configuration
- [ ] Flyway baseline applied to existing databases (`spring.flyway.baseline-on-migrate=true`)

---

### US-E3-003: Database schema migration — outbox_messages table with LISTEN/NOTIFY trigger
**As a** developer, **I want** the `outbox_messages` table with a PostgreSQL NOTIFY trigger, **so that** the outbox poller is triggered near-instantly when a new outbox record is inserted.

**SP:** 3 | **Sprint:** 3 | **Deps:** US-E3-002

**AC:**
- [ ] Flyway migration `V2__create_outbox_messages.sql` creates table with all columns in REQ-DB-011
- [ ] Index on `status`, `created_at`
- [ ] PostgreSQL trigger `outbox_notify_trigger` on INSERT executes `NOTIFY hermes_outbox_channel, 'new'`
- [ ] Trigger fires for each inserted row (not per statement)
- [ ] Flyway migration `V3__create_indexes.sql` adds any supplementary indexes
- [ ] Local test: insert a row into `outbox_messages` and confirm NOTIFY is received by a `psql LISTEN hermes_outbox_channel` listener

---

### US-E3-004: HikariCP connection pool configuration
**As a** developer, **I want** HikariCP configured with correct pool sizing for the concurrent processing model, **so that** connection pool is neither exhausted nor wasteful.

**SP:** 2 | **Sprint:** 3 | **Deps:** US-E3-001

**AC:**
- [ ] `spring.datasource.hikari.maximum-pool-size=20` (16 threads + headroom, per REQ-PERF-011)
- [ ] `spring.datasource.hikari.minimum-idle=5`
- [ ] `spring.datasource.hikari.connection-timeout=30000` ms
- [ ] `spring.datasource.hikari.idle-timeout=600000` ms
- [ ] `spring.datasource.hikari.max-lifetime=1800000` ms
- [ ] `spring.datasource.hikari.keepalive-time=300000` ms (for RDS Proxy idle connection management)
- [ ] Pool metrics exposed via Spring Boot Actuator and scraped by ADOT
- [ ] Connection string uses RDS Proxy endpoint (not RDS direct endpoint) in production

---

## Epic E4: Messaging Infrastructure (SNS FIFO / SQS FIFO)
**Goal:** SNS FIFO and SQS FIFO infrastructure provisioned via Terraform. Ready for outbox poller to publish.

---

### US-E4-001: SNS FIFO topic for flightschedules
**As a** developer, **I want** an SNS FIFO topic for the flightschedules destination, **so that** messages can be fanned out to multiple SQS FIFO queues.

**SP:** 3 | **Sprint:** 3 | **Deps:** US-E1-003, US-E1-004

**AC:**
- [ ] SNS FIFO topic `hermes-flightschedules.fifo` created
- [ ] SSE-KMS with CMK `hermes-sns-key`
- [ ] Content-based deduplication: **disabled** (explicit `MessageDeduplicationId` used by app)
- [ ] High-throughput mode: enabled
- [ ] Access policy: only `hermes-flightschedules-role` (IRSA) can `sns:Publish`
- [ ] Delivery status logging to CloudWatch enabled for SQS endpoints
- [ ] Topic ARN output from Terraform module

---

### US-E4-002: SQS FIFO queues and DLQ for flightschedules
**As a** developer, **I want** SQS FIFO queues and a DLQ for the flightschedules destination, **so that** downstream consumers can process messages independently with exactly-once delivery semantics.

**SP:** 3 | **Sprint:** 3 | **Deps:** US-E4-001

**AC:**
- [ ] SQS FIFO queue `hermes-flightschedules-consumer-a.fifo` (extensible pattern for more consumers)
- [ ] DLQ FIFO queue `hermes-flightschedules-dlq.fifo`
- [ ] `maxReceiveCount=3` on main queue (after 3 failures, message goes to DLQ)
- [ ] SSE-KMS with CMK `hermes-sqs-key`
- [ ] High-throughput FIFO mode enabled on main queue
- [ ] `WaitTimeSeconds=20` (long polling)
- [ ] Visibility timeout: `180` seconds (configurable; 6× assumed 30s downstream processing time)
- [ ] Message retention: 14 days
- [ ] SNS → SQS subscription created with raw message delivery enabled
- [ ] SQS queue policy allows `sqs:SendMessage` from SNS FIFO topic only
- [ ] Queue ARNs output from Terraform

---

### US-E4-003: SNS/SQS message group strategy configuration
**As a** developer, **I want** the `MessageGroupId` strategy documented and implemented as configurable, **so that** we can tune parallelism vs. ordering based on destination requirements.

**SP:** 2 | **Sprint:** 3 | **Deps:** US-E4-001

**AC:**
- [ ] Default `MessageGroupId` = destination name (`flightschedules`) for global ordering
- [ ] Alternative strategy configurable: hash of `correlationId` modulo N (for higher parallelism)
- [ ] Strategy selected via `application.yml` property `hermes.messaging.message-group-id-strategy`
- [ ] `MessageDeduplicationId` = outbox record `deduplication_id` (Solace message ID)
- [ ] Strategy documented in Architecture Decision Record `docs/adr/ADR-003-message-group-id-strategy.md`

---

## Epic E5: Spring Boot Application Foundation
**Goal:** Spring Boot application connects to Solace via JCSMP with mTLS, receives messages, and reports health correctly.

---

### US-E5-001: Spring Boot project scaffold
**As a** developer, **I want** a Spring Boot 3.x project with all required dependencies and build configuration, **so that** I have a clean foundation to build on.

**SP:** 3 | **Sprint:** 3 | **Deps:** US-E0-005

**AC:**
- [ ] Maven project with: `spring-boot-starter-web`, `spring-boot-starter-actuator`, `spring-boot-starter-data-jpa`, `spring-boot-starter-validation`, `solace-spring-boot-starter` (JCSMP), `aws-sdk-v2` (SNS, SQS, S3, Secrets Manager), `resilience4j-spring-boot3`, `flyway-core`, `micrometer-registry-cloudwatch2`, `opentelemetry-sdk`, `logback-json-encoder`
- [ ] Multi-stage Dockerfile: Maven build stage + UBI 9 + Eclipse Temurin JRE 17 runtime stage
- [ ] Image built successfully: `docker build -t hermes-consumer:local .`
- [ ] JVM flags: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75` in `JAVA_OPTS`
- [ ] Spring profiles: `local`, `staging`, `prod`
- [ ] `.gitignore` excludes: `*.p12`, `*.jks`, `*.env`, `target/`, `*.tfstate`

---

### US-E5-002: JCSMP FlowReceiver with mTLS configuration
**As a** developer, **I want** JCSMP configured with mTLS (client certificate authentication) and a FlowReceiver bound to the `flightschedules` queue, **so that** the application can receive guaranteed messages from Solace.

**SP:** 8 | **Sprint:** 3–4 | **Deps:** US-E5-001, US-E0-002

**AC:**
- [ ] `SolaceJcsmpConfig.java`: creates `JCSMPSession` with all properties from REQ-SOL-004
- [ ] TLS configuration: `JCSMPProperties.SSL_PROTOCOL = "TLSv1.2"`, cipher suites restricted
- [ ] mTLS: `SSL_KEY_STORE` = path to PKCS12 keystore (from mounted K8s Secret volume in AWS; from file in local), `SSL_KEY_STORE_PASSWORD`, `SSL_TRUST_STORE`, `SSL_TRUST_STORE_PASSWORD`
- [ ] `client-name` = `aws-hermes-flightschedules-{pod-uid}` (pod UID injected from Downward API env var `POD_UID`)
- [ ] `reconnectRetries = -1`, `reconnectRetryWaitInMillis = 3000`
- [ ] `subAckWindowSize = 32`, `socketReceiveBufferSize = 131072`, `compressionLevel = 6`
- [ ] `FlowReceiver` bound to queue `hermes.flightschedules` with `SUPPORTED_MESSAGE_ACK_CLIENT_INDIVIDUAL`
- [ ] `XMLMessageListener.onReceive()` dispatches messages to processing thread pool
- [ ] `FlowEventHandler` logs flow lifecycle events
- [ ] Flow starts on application startup; stops on SIGTERM
- [ ] Local test: app connects to Docker Compose Solace with self-signed certs and receives a test message

---

### US-E5-003: Solace SessionEventHandler and reconnection lifecycle
**As a** developer, **I want** a `SessionEventHandler` that logs all connection lifecycle events and exposes connection status as a Spring Boot Actuator health indicator, **so that** disconnections are visible in monitoring and Kubernetes readiness probes react correctly.

**SP:** 3 | **Sprint:** 4 | **Deps:** US-E5-002

**AC:**
- [ ] `SolaceSessionEventHandler` handles: `SESSION_UP`, `SESSION_DOWN`, `RECONNECTING`, `RECONNECTED`
- [ ] Each event logged at appropriate level: `SESSION_DOWN` = ERROR, `RECONNECTING` = WARN, `RECONNECTED` = INFO
- [ ] Connection status maintained as an `AtomicBoolean` (thread-safe)
- [ ] `SolaceHealthIndicator` implements `HealthIndicator`: `UP` when connected, `DOWN` when session is down
- [ ] `SolaceHealthIndicator` registered as readiness health indicator (`/actuator/health/readiness`)
- [ ] Readiness probe returns HTTP 503 when Solace session is down (removes pod from Service endpoints)
- [ ] Custom CloudWatch metric `solace.connection.status` (1=UP, 0=DOWN) emitted on every status change
- [ ] Test: stop Solace container → readiness probe fails within 10 seconds; restart Solace → reconnects within 9 seconds (3 retries × 3s)

---

### US-E5-004: Structured JSON logging baseline
**As a** developer, **I want** all application logs in structured JSON format with required fields, **so that** CloudWatch Logs Insights can filter and query logs efficiently.

**SP:** 2 | **Sprint:** 4 | **Deps:** US-E5-001

**AC:**
- [ ] Logback configured with `logstash-logback-encoder` or `logback-json` to output JSON to stdout
- [ ] Every log entry contains: `timestamp`, `level`, `correlationId`, `messageId`, `destination`, `podName`, `threadName`, `logger`, `message`, `traceId`
- [ ] MDC populated with `correlationId`, `messageId`, `destination` at message receipt
- [ ] MDC cleared after processing completes (via `try/finally`)
- [ ] Logs do NOT contain message payload (privacy + log size control)
- [ ] Log level configurable via environment variable `LOG_LEVEL` (default: `INFO`)
- [ ] `DEBUG` level logs message receipt and processing steps when enabled

---

## Epic E6: Core Message Processing (Transactional Outbox)
**Goal:** Full message processing pipeline works: Solace message → validation → idempotency check → audit + outbox (single TX) → Solace ACK → LISTEN/NOTIFY → outbox poller → SNS FIFO publish.

---

### US-E6-001: FlightSchedule canonical data model and deserialisation
**As a** developer, **I want** a `FlightScheduleMessage` POJO that deserialises Solace message payloads, **so that** the application works with a typed domain model.

**SP:** 2 | **Sprint:** 4 | **Deps:** US-E5-002

**AC:**
- [ ] `FlightScheduleMessage` DTO with Jackson annotations
- [ ] Fields: at minimum `flightNumber`, `departureAirport`, `arrivalAirport`, `scheduledDepartureUtc`, `scheduledArrivalUtc`, `status`, and a correlation ID field
- [ ] Deserialisation handles both `TextMessage` and `BytesMessage` from JCSMP
- [ ] Unknown fields are tolerated (`@JsonIgnoreProperties(ignoreUnknown = true)`)
- [ ] Sample test message JSON documented in `local-dev/test-data/flight-schedule-sample.json`
- [ ] A sample message >200 KB is also available for claim-check testing

---

### US-E6-002: Message validation (schema + size check)
**As a** developer, **I want** incoming messages validated for schema and size before processing, **so that** invalid or oversized messages are rejected gracefully and routed to the DLQ.

**SP:** 2 | **Sprint:** 4 | **Deps:** US-E6-001

**AC:**
- [ ] Bean Validation (`@NotNull`, `@Size`, `@NotBlank`) on required fields of `FlightScheduleMessage`
- [ ] Payload size check: if `payloadSizeBytes > 200_000`, trigger claim-check path (not reject)
- [ ] If JSON deserialization fails: log error with full message ID, route to DLQ, NACK message (do not retry)
- [ ] If validation fails: log validation errors, route to DLQ, do not acknowledge
- [ ] Validation errors include message ID in log for traceability

---

### US-E6-003: Idempotent consumer — duplicate detection
**As a** developer, **I want** duplicate Solace messages (same `message_id`) to be silently skipped after the first processing, **so that** redeliveries due to pod crashes or prefetch buffer redelivery do not create duplicate audit records.

**SP:** 3 | **Sprint:** 4 | **Deps:** US-E6-001, US-E3-002

**AC:**
- [ ] Before insert, query `SELECT id FROM audit_messages WHERE message_id = ?`
- [ ] If exists: log `WARN "Duplicate message skipped: {messageId}"`, acknowledge to Solace, return
- [ ] If not exists: proceed with transactional processing
- [ ] The `UNIQUE` constraint on `message_id` is the final guard (handles race conditions between concurrent threads)
- [ ] On `DataIntegrityViolationException` (concurrent duplicate): treat as duplicate skip, acknowledge, do not retry
- [ ] Metric `solace.messages.duplicate.skipped` emitted when duplicate is detected

---

### US-E6-004: Transactional Outbox — single database transaction
**As a** developer, **I want** the audit record and outbox record written in a single `@Transactional` method, **so that** there is no dual-write inconsistency — if the DB transaction rolls back, neither record exists, and the message will be redelivered.

**SP:** 5 | **Sprint:** 4 | **Deps:** US-E6-003, US-E3-003

**AC:**
- [ ] `MessageProcessingService.processMessage()` annotated `@Transactional(propagation=REQUIRED, isolation=READ_COMMITTED)`
- [ ] Within transaction: (1) insert `audit_messages` row with status `RECEIVED`; (2) insert `outbox_messages` row with `status=PENDING`, `deduplication_id=solace-message-id`, `message_group_id=flightschedules`
- [ ] Transaction commits before Solace ACK is sent
- [ ] Solace `INDIVIDUAL_ACKNOWLEDGE` called immediately after successful transaction commit
- [ ] If transaction rolls back (DB error): Solace message is NOT acknowledged → Solace redelivers
- [ ] Thread pool for processing: 16 threads (configurable via `hermes.consumer.thread-pool-size`), backed by a `ThreadPoolTaskExecutor` with queue capacity 32 (matching prefetch)
- [ ] Each thread acquires its own DB connection from HikariCP

---

### US-E6-005: Outbox poller with LISTEN/NOTIFY and fallback polling
**As a** developer, **I want** the outbox poller triggered via PostgreSQL `LISTEN/NOTIFY` with 500ms fallback polling, **so that** messages are published to SNS FIFO with minimal latency after the DB transaction commits.

**SP:** 5 | **Sprint:** 4–5 | **Deps:** US-E6-004

**AC:**
- [ ] `OutboxPollerService` maintains a dedicated `LISTEN hermes_outbox_channel` connection (separate from HikariCP pool — use a dedicated `PGConnection`)
- [ ] On NOTIFY received: immediately trigger `pollAndPublish()`
- [ ] Fallback `@Scheduled(fixedDelay=500)` also triggers `pollAndPublish()` independently
- [ ] `pollAndPublish()`: `SELECT * FROM outbox_messages WHERE status='PENDING' ORDER BY created_at LIMIT 100 FOR UPDATE SKIP LOCKED`
- [ ] For each fetched row: publish to SNS FIFO; on success update `status='PUBLISHED'`, `published_at=NOW()`; on failure increment retry, update `status='FAILED'`
- [ ] `LISTEN` connection reconnects automatically if dropped (exponential backoff reconnect)
- [ ] Metric `outbox.pending.count` (count of rows WHERE status='PENDING') published every 30 seconds
- [ ] Metric `outbox.notify.latency` (time between outbox INSERT and poller pickup) measured and published

---

### US-E6-006: SNS FIFO publish from outbox poller
**As a** developer, **I want** the outbox poller to publish to SNS FIFO using async batching, **so that** throughput is maximised and SNS API calls are efficient.

**SP:** 5 | **Sprint:** 5 | **Deps:** US-E6-005, US-E4-001

**AC:**
- [ ] AWS SDK v2 SNS async client (`SnsAsyncClient`) used for non-blocking publish
- [ ] Batch publish using `PublishBatch` (up to 10 messages per call)
- [ ] Each publish request includes: `MessageDeduplicationId` = `outbox.deduplication_id`, `MessageGroupId` = `outbox.message_group_id`
- [ ] Message attributes include: `messageType`, `sourceSystem=solace-hermes`, `sourceDestination=flightschedules`, `correlationId`, `timestamp`
- [ ] On `SnsException`: retry via Resilience4j (Epic E8); after max retries, set status `FAILED`
- [ ] After successful batch publish: update all matching outbox rows to `PUBLISHED`, populate `audit_messages.sns_message_id` and `status=PUBLISHED`
- [ ] Metric `sns.publish.latency` measured per batch call

---

## Epic E7: Claim-Check Pattern (Large Messages)
**Goal:** Messages exceeding 200 KB are stored in S3. SNS receives only a reference. Downstream consumers can retrieve the full payload.

---

### US-E7-001: Large message detection and S3 storage
**As a** developer, **I want** messages larger than 200 KB to be automatically stored in S3, **so that** SNS/SQS message size limits are never breached.

**SP:** 5 | **Sprint:** 5 | **Deps:** US-E6-001, US-E1-007

**AC:**
- [ ] After deserialisation, compute `payloadSizeBytes` = raw payload byte length
- [ ] If `payloadSizeBytes > 200_000`: upload raw payload to S3 `hermes-claim-check-{env}/{destination}/{messageId}.json` using AWS SDK v2 S3 async client; server-side encryption with KMS CMK
- [ ] Construct `ClaimCheckReference`: `{ "s3Uri": "s3://...", "payloadSizeBytes": N, "contentType": "application/json", "messageId": "...", "destination": "flightschedules" }`
- [ ] Outbox payload = serialized `ClaimCheckReference` (not full payload)
- [ ] Audit `message_payload` column stores `ClaimCheckReference` JSON, not full payload
- [ ] `payload_hash` (SHA-256) of the full payload stored in audit for integrity verification
- [ ] Metric `claim.check.uploads` counter incremented on each upload

---

### US-E7-002: Claim-check reference in SNS message
**As a** developer, **I want** downstream consumers to know they are receiving a claim-check reference vs. an inline payload, **so that** they can retrieve the full payload from S3 when needed.

**SP:** 2 | **Sprint:** 5 | **Deps:** US-E7-001

**AC:**
- [ ] SNS message attribute `payloadType` = `INLINE` for normal messages, `CLAIM_CHECK` for S3-referenced messages
- [ ] SNS message body for claim-check messages is the serialised `ClaimCheckReference` JSON
- [ ] Downstream consumer documentation: how to detect `CLAIM_CHECK` type and retrieve from S3
- [ ] S3 object tagging: `messageId`, `destination`, `environment` for lifecycle management
- [ ] Integration test: publish message >200KB → confirm S3 object exists → confirm SNS contains reference → confirm downstream can reconstruct full payload from reference

---

## Epic E8: Resilience & Reliability
**Goal:** Circuit breakers, retry, bulkhead, backpressure, DLQ routing, and graceful shutdown are implemented. The system self-heals without message loss.

---

### US-E8-001: Circuit breakers for RDS and SNS
**As a** developer, **I want** Resilience4j circuit breakers on RDS and SNS calls, **so that** downstream failures do not cause thread pool saturation and Solace consumption is paused when downstream services are unavailable.

**SP:** 5 | **Sprint:** 5 | **Deps:** US-E6-004, US-E6-006

**AC:**
- [ ] Circuit breaker `rds-write` wraps `MessageProcessingService.processMessage()`
- [ ] Circuit breaker `sns-publish` wraps `OutboxPollerService.publishToSns()`
- [ ] Config: `slidingWindowSize=10`, `failureRateThreshold=50`, `waitDurationInOpenState=30s`, `permittedNumberOfCallsInHalfOpenState=5`, `minimumNumberOfCalls=5`
- [ ] On circuit breaker OPEN: `FlowReceiver.stop()` is called (backpressure to Solace) — NO in-memory message buffering
- [ ] On circuit breaker CLOSED (after half-open probes succeed): `FlowReceiver.start()` resumes
- [ ] Circuit breaker state changes logged at WARN and metric `circuit.breaker.state` published
- [ ] Test: simulate RDS failure → confirm circuit opens after 5 failures, FlowReceiver stops, Solace messages queue on broker; RDS recovered → circuit closes, FlowReceiver resumes

---

### US-E8-002: Retry with exponential backoff and jitter
**As a** developer, **I want** all external calls to retry with exponential backoff and jitter, **so that** transient failures are handled gracefully without thundering herd effects.

**SP:** 3 | **Sprint:** 5 | **Deps:** US-E8-001

**AC:**
- [ ] Resilience4j Retry configured: `maxAttempts=3`, `waitDuration=100ms`, `multiplier=2`, `randomizationFactor=0.2`, `maxWaitDuration=10s`
- [ ] Retry applied to: RDS transaction, SNS publish, S3 upload
- [ ] Retry NOT applied to Solace reconnection (handled by JCSMP built-in fixed-interval, not Resilience4j)
- [ ] After max retries exhausted: exception propagated to circuit breaker
- [ ] Each retry attempt logged at DEBUG with attempt number and wait time

---

### US-E8-003: Bulkhead — separate thread pools
**As a** developer, **I want** separate thread pools for Solace consumption, RDS writes, and SNS publishes, **so that** a slow downstream service cannot starve the other processing paths.

**SP:** 3 | **Sprint:** 6 | **Deps:** US-E8-002

**AC:**
- [ ] `SolaceConsumerThreadPool`: 16 threads, queue capacity 32 — receives Solace messages, dispatches to processing
- [ ] `RdsWriteThreadPool`: 16 threads — executes DB transactions
- [ ] `SnsPublishThreadPool`: 8 threads (async SNS SDK handles its own I/O; thread pool for batching orchestration)
- [ ] `OutboxListenThreadPool`: 1 dedicated thread for PostgreSQL LISTEN connection
- [ ] Thread pool metrics exposed via Actuator and shipped to CloudWatch
- [ ] Resilience4j Bulkhead wraps each external call with matching pool sizes

---

### US-E8-004: DLQ routing for persistently failing messages
**As a** developer, **I want** messages that fail after maximum retries to be routed to the DLQ with full context, **so that** they can be investigated and replayed without blocking other messages.

**SP:** 3 | **Sprint:** 6 | **Deps:** US-E8-002

**AC:**
- [ ] After 3 failed processing attempts: update `audit_messages.status = 'DLQ'`, `error_message` = last exception message
- [ ] Message published to SQS DLQ FIFO `hermes-flightschedules-dlq.fifo` with full context (message ID, destination, error, timestamp)
- [ ] Solace message acknowledged after DLQ routing (to prevent infinite redelivery loop)
- [ ] CloudWatch Alarm fires immediately when DLQ FIFO visible count > 0
- [ ] DLQ message includes enough context for a human operator to decide whether to replay

---

### US-E8-005: Graceful shutdown (SIGTERM handler)
**As a** developer, **I want** the application to shut down gracefully on SIGTERM, **so that** in-flight messages complete processing and the outbox is flushed before the pod terminates.

**SP:** 3 | **Sprint:** 6 | **Deps:** US-E8-003

**AC:**
- [ ] `@PreDestroy` or `ApplicationListener<ContextClosedEvent>`: (1) call `FlowReceiver.stop()` immediately on SIGTERM; (2) wait for active processing threads to complete (up to 55s); (3) flush any `PENDING` outbox records owned by this instance; (4) call `JCSMPSession.closeSession()`
- [ ] `terminationGracePeriodSeconds: 60` in pod spec
- [ ] `preStop` lifecycle hook: `sleep 5` to allow load balancer to stop routing new connections
- [ ] If flush takes >55s: log WARN and proceed — orphaned outbox records picked up by other pods via SKIP LOCKED
- [ ] Test: `kubectl delete pod hermes-xxx` → confirm current message completes → confirm outbox flushed → confirm clean Solace disconnect in logs

---

## Epic E9: ROSA Container Deployment
**Goal:** Application fully deployed to ROSA via Helm with HPA, KEDA, anti-affinity, PDB, and all secrets injected.

---

### US-E9-001: Helm chart scaffold
**As a** developer, **I want** a Helm chart that templates all ROSA application resources, **so that** deployments are repeatable, environment-specific, and diff-able in Git.

**SP:** 5 | **Sprint:** 6 | **Deps:** US-E5-001

**AC:**
- [ ] Chart structure: `helm/hermes/Chart.yaml`, `templates/`, `values.yaml`, `values-local.yaml`, `values-staging.yaml`, `values-prod.yaml`
- [ ] Templates: `deployment.yaml`, `service.yaml` (ClusterIP, port 8080/8081), `configmap.yaml`, `serviceaccount.yaml`, `hpa.yaml`, `keda-scaledobject.yaml`, `pdb.yaml`, `networkpolicy.yaml`, `externalsecret.yaml`, `rolebinding.yaml`
- [ ] `helm lint` passes with no errors or warnings
- [ ] `helm template` renders correct manifests for each environment
- [ ] Chart version follows SemVer; app version = Docker image tag

---

### US-E9-002: Kubernetes probes and resource configuration
**As a** developer, **I want** correct liveness, readiness, and startup probes with appropriate resource requests/limits, **so that** Kubernetes can correctly manage pod lifecycle and the scheduler can bin-pack pods efficiently.

**SP:** 3 | **Sprint:** 6 | **Deps:** US-E9-001, US-E5-003

**AC:**
- [ ] `startupProbe`: HTTP GET `/actuator/health`, `failureThreshold=30`, `periodSeconds=10` (30× = 5 min startup tolerance for initial Solace connection)
- [ ] `livenessProbe`: HTTP GET `/actuator/health/liveness`, `initialDelaySeconds=0`, `periodSeconds=10`, `failureThreshold=3`
- [ ] `readinessProbe`: HTTP GET `/actuator/health/readiness`, `periodSeconds=5`, `failureThreshold=2` (Solace + RDS connected)
- [ ] Resources: `requests: {cpu: "1", memory: "2Gi"}`, `limits: {cpu: "2", memory: "4Gi"}`
- [ ] JVM: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75` (3 GiB heap within 4 GiB limit)
- [ ] `securityContext`: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `drop: [ALL]`
- [ ] Management server on port 8081 (separate from application port 8080)

---

### US-E9-003: Pod anti-affinity and topology spread
**As a** developer, **I want** pods distributed across AZs, **so that** an AZ failure does not take down all pods for the flightschedules consumer.

**SP:** 2 | **Sprint:** 6 | **Deps:** US-E9-001

**AC:**
- [ ] `topologySpreadConstraints`: `maxSkew=1`, `topologyKey=topology.kubernetes.io/zone`, `whenUnsatisfiable=DoNotSchedule`
- [ ] `podAntiAffinity` (preferred): discourage same node for same Deployment
- [ ] Pod Disruption Budget: `minAvailable=1` (ensures at least 1 pod always available during drains)
- [ ] Test: `kubectl cordon` one node and `kubectl drain` → PDB prevents both pods being evicted simultaneously

---

### US-E9-004: HPA and KEDA auto-scaling
**As a** developer, **I want** the flightschedules Deployment to auto-scale based on CPU and outbox pending count, **so that** message processing keeps up with load automatically.

**SP:** 5 | **Sprint:** 7 | **Deps:** US-E9-001, US-E10 (CloudWatch metric must exist)

**AC:**
- [ ] HPA: `minReplicas=2`, `maxReplicas=10`, scale out when avg CPU > 70% for 3 min, scale in when < 30% for 10 min with `stabilizationWindowSeconds=300`
- [ ] KEDA `ScaledObject`: trigger on CloudWatch metric `outbox.pending.count` in namespace `CustomerMiddleware` with dimension `Destination=flightschedules`; threshold=100 (add pod per 100 pending); `minReplicaCount=2`, `maxReplicaCount=10`
- [ ] KEDA IRSA: `ScaledObject` uses ServiceAccount with CloudWatch read permissions
- [ ] HPA and KEDA coexist correctly (KEDA manages HPA internally when `ScaledObject` is used)
- [ ] Test: artificially backfill 500 outbox records → confirm KEDA triggers scale-out to 5+ pods within 3 minutes

---

### US-E9-005: ConfigMaps and ExternalSecrets in Helm
**As a** developer, **I want** application configuration sourced from SSM Parameter Store via ESO and secrets from Secrets Manager, **so that** destination-specific configuration can be changed without rebuilding the container image.

**SP:** 3 | **Sprint:** 6 | **Deps:** US-E2-003, US-E9-001

**AC:**
- [ ] `ExternalSecret` syncs Solace credentials, keystore, truststore, DB credentials to K8s Secrets
- [ ] `ConfigMap` sources from SSM Parameter Store via ESO (Solace host, VPN name, destination name, queue name, SNS topic ARN)
- [ ] Keystore and truststore mounted as volumes at `/etc/hermes/certs/` (readOnly)
- [ ] All secrets referenced as env vars or volume mounts (never as literals in YAML)
- [ ] Pod UID injected via Downward API: `env.POD_UID = metadata.uid`
- [ ] New destination can be added by creating new SSM parameters + Helm values override only (no code change)

---

## Epic E10: Observability
**Goal:** Full observability stack: ADOT shipping metrics/logs/traces, all CloudWatch alarms active, dashboard live.

---

### US-E10-001: ADOT Collector DaemonSet deployment
**As a** developer, **I want** ADOT Collector running as a DaemonSet on ROSA, **so that** application metrics, logs, and traces are automatically collected and shipped to CloudWatch and X-Ray.

**SP:** 5 | **Sprint:** 7 | **Deps:** US-E9-001, US-E2-002

**AC:**
- [ ] ADOT Operator installed via OperatorHub (OLM)
- [ ] `OpenTelemetryCollector` CR deployed as DaemonSet with IRSA ServiceAccount
- [ ] Receivers: Prometheus scrape (Actuator `/actuator/prometheus` on port 8081), OTLP (gRPC port 4317)
- [ ] Exporters: CloudWatch EMF (metrics), CloudWatch Logs (logs), X-Ray (traces)
- [ ] Scrape config targets `hermes` namespace pods with label `app.kubernetes.io/name=hermes-consumer`
- [ ] ADOT pods have resource limits and IRSA annotation

---

### US-E10-002: Custom CloudWatch metrics via Micrometer
**As a** developer, **I want** all 11 custom CloudWatch metrics from REQ-MON-001 instrumented in the application, **so that** dashboards and alarms have real data.

**SP:** 5 | **Sprint:** 7 | **Deps:** US-E6-004, US-E6-006, US-E10-001

**AC:**
- [ ] `MeterRegistry` (CloudWatch Micrometer) injected into all service beans
- [ ] Counters: `solace.messages.received`, `solace.messages.processed`, `solace.messages.failed` (all with `destination` tag)
- [ ] Gauge: `solace.connection.status` (1/0), `outbox.pending.count`
- [ ] Timers: `audit.insert.latency`, `sns.publish.latency`, `processing.e2e.latency`, `outbox.notify.latency`
- [ ] Counter: `solace.reconnect.count`
- [ ] All metrics in CloudWatch namespace `CustomerMiddleware` with dimension `Destination=flightschedules`, `Environment={env}`
- [ ] SEMP monitoring sidecar container (or CronJob) polls SEMPv2 every 30s for `solace.dmq.depth` and queue metrics and publishes to CloudWatch

---

### US-E10-003: CloudWatch Alarms
**As a** developer, **I want** all 10 CloudWatch Alarms from REQ-MON-010 configured via Terraform, **so that** operational issues are detected and escalated automatically.

**SP:** 5 | **Sprint:** 7 | **Deps:** US-E10-002

**AC:**
- [ ] All 10 alarms from REQ-MON-010 created via Terraform `monitoring` module
- [ ] Alarm actions: SNS notification topic for alerts (configure PagerDuty/Slack webhook as subscription)
- [ ] Certificate expiry Lambda runs daily, publishes days-remaining metric → alarm at 14 days
- [ ] Additional alarms per REQ-MSG-022 for SNS/SQS FIFO metrics
- [ ] Additional alarms per REQ-SOL-041 for Solace SEMP metrics
- [ ] All alarms in `OK` state at rest (no false positives)
- [ ] CloudWatch alarm names follow convention: `hermes-{destination}-{issue}-{env}`

---

### US-E10-004: X-Ray distributed tracing
**As a** developer, **I want** end-to-end distributed traces from Solace message receipt through RDS and SNS, **so that** I can diagnose latency issues across the processing pipeline.

**SP:** 3 | **Sprint:** 7 | **Deps:** US-E10-001

**AC:**
- [ ] OpenTelemetry SDK instrumented in Spring Boot application
- [ ] Custom spans: `solace.message.receive`, `db.transaction`, `sns.publish`, `outbox.poll`
- [ ] Trace propagated through async thread pool boundaries (baggage propagation)
- [ ] Span attributes: `messageId`, `correlationId`, `destination`, `payloadSizeBytes`
- [ ] Traces exported via ADOT to X-Ray
- [ ] X-Ray service map shows: App → RDS → SNS
- [ ] Sampling rate: 10% default, 100% for errors

---

### US-E10-005: CloudWatch Dashboard
**As a** developer, **I want** a CloudWatch Dashboard with per-destination views showing all key metrics, **so that** I can monitor the system health at a glance.

**SP:** 3 | **Sprint:** 8 | **Deps:** US-E10-002, US-E10-003

**AC:**
- [ ] Dashboard `hermes-operations-{env}` defined as JSON in Terraform
- [ ] Widgets: real-time throughput (received/processed/failed), E2E latency percentiles (P50/P95/P99), connection status indicator, RDS metrics, SNS/SQS metrics, pod count + CPU/memory, outbox pending count trend, SEMP metrics (DMQ depth, queue depth)
- [ ] Dashboard auto-refreshes every 1 minute
- [ ] Dashboard URL documented in operational runbook

---

## Epic E11: CI/CD Pipeline
**Goal:** Fully automated pipeline from code commit to production deployment with all quality gates.

---

### US-E11-001: AWS CodePipeline and CodeBuild setup
**As a** developer, **I want** an AWS CodePipeline that automatically builds, tests, scans, and deploys on every commit, **so that** quality is enforced continuously and deployments are automated.

**SP:** 8 | **Sprint:** 8 | **Deps:** US-E1-006, US-E9-001

**AC:**
- [ ] CodePipeline stages: Source → Build → Test → SecurityScan → ContainerBuild → IntegrationTest → PerfSmokeTest → DeployStaging → ManualApproval → DeployProd
- [ ] CodeBuild: Maven build + JUnit 5 (>80% coverage gate fails build if below)
- [ ] CodeBuild: SonarQube or CodeGuru static analysis (no critical/blocker issues gate)
- [ ] CodeBuild: Trivy container scan (fails on HIGH/CRITICAL CVEs)
- [ ] CodeBuild: multi-stage Docker build, push to ECR with git commit SHA tag + `latest`
- [ ] CodeBuild: Testcontainers integration tests (Solace + PostgreSQL containers)
- [ ] CodeBuild: SDKPerf 5-min smoke performance test (1000 msg/s, P95<500ms gate)
- [ ] `helm upgrade --install --atomic` to staging; smoke test passes
- [ ] Manual approval gate before production deployment
- [ ] `helm upgrade --install --atomic --set maxUnavailable=0,maxSurge=1` to production
- [ ] Automatic `helm rollback` if readiness probes fail within 5 minutes

---

### US-E11-002: Testcontainers integration test suite
**As a** developer, **I want** integration tests using Testcontainers that spin up real Solace and PostgreSQL containers, **so that** message flow is tested end-to-end without mocks.

**SP:** 8 | **Sprint:** 8 | **Deps:** US-E6-006

**AC:**
- [ ] `@SpringBootTest` with `@Testcontainers` annotation
- [ ] Solace PubSub+ Standard container started automatically
- [ ] PostgreSQL container started automatically with Flyway migrations applied
- [ ] LocalStack container for SNS/SQS/S3
- [ ] Test: publish 10 messages → verify all in `audit_messages` with status `PUBLISHED`
- [ ] Test: publish duplicate message → verify idempotent skip
- [ ] Test: publish message >200 KB → verify claim-check in S3
- [ ] Test: simulate DB failure → verify circuit breaker opens, FlowReceiver stops
- [ ] Tests run in CI/CD in < 5 minutes

---

## Epic E12: Load Testing
**Goal:** All load test scenarios from Section 10 pass success criteria.

---

### US-E12-001: Load test environment setup
**As a** developer, **I want** a dedicated ROSA namespace mirroring production topology for load testing, **so that** performance tests do not impact production.

**SP:** 3 | **Sprint:** 9 | **Deps:** US-E9-001

**AC:**
- [ ] Namespace `hermes-perf` with same Helm chart and `values-perf.yaml`
- [ ] SDKPerf binary available in a CodeBuild environment or EC2 instance within VPC
- [ ] JMeter scripts for HTTP actuator endpoint testing
- [ ] Load test results stored in S3 `hermes-logs-{env}/load-tests/`

---

### US-E12-002: Baseline, burst, and endurance tests
**As a** developer, **I want** baseline (1000 msg/s), burst (3000 msg/s), and endurance (800 msg/s × 8h) tests executed and passing success criteria, **so that** the system's performance is validated before production go-live.

**SP:** 5 | **Sprint:** 9 | **Deps:** US-E12-001

**AC:**
- [ ] Baseline: 1000 msg/s × 1 hour → P95 < 500ms, zero message loss, CPU < 70%
- [ ] Burst: 3000 msg/s × 15 min → P99 < 2s, zero message loss
- [ ] Endurance: 800 msg/s × 8 hours → no OOM, no thread exhaustion, no memory leak (heap stable)
- [ ] Results documented in `load-tests/results/`

---

### US-E12-003: Failure and recovery tests
**As a** developer, **I want** reconnection, DB failover, scaling, and node-kill tests executed, **so that** resilience mechanisms are validated under realistic failure conditions.

**SP:** 8 | **Sprint:** 9 | **Deps:** US-E12-002

**AC:**
- [ ] Reconnection test: cut Solace connection mid-load → verify reconnect < 9s, zero message loss
- [ ] DB Failover test: trigger RDS failover mid-load → verify backpressure, recovery, zero data loss
- [ ] Scaling test: ramp from 200 to 2000 msg/s → verify HPA/KEDA scales to 10 pods within 3 minutes
- [ ] Node Kill test: terminate a worker node → verify pod rescheduling, no message loss
- [ ] All success criteria REQ-LT-004 through REQ-LT-011 met and documented

---

## Epic E13: DR Validation & Operationalisation
**Goal:** Multi-AZ DR validated. Runbooks written and tested. Production go-live ready.

---

### US-E13-001: Multi-AZ failover validation
**As a** developer, **I want** Multi-AZ failover tested under load, **so that** the 99.9% availability target is achievable.

**SP:** 3 | **Sprint:** 9 | **Deps:** US-E12-003

**AC:**
- [ ] Trigger RDS Multi-AZ failover (`aws rds reboot-db-instance --force-failover`) under 500 msg/s load
- [ ] Confirm: circuit breaker opens, FlowReceiver stops, messages queue on Solace broker
- [ ] Confirm: RDS failover completes < 60 seconds
- [ ] Confirm: application reconnects to new primary via RDS Proxy transparently
- [ ] Confirm: zero message loss (audit count matches publish count)
- [ ] Evict all pods from one AZ via node taint → confirm PDB prevents simultaneous eviction, pods reschedule to surviving AZ

---

### US-E13-002: DR and operational runbooks
**As a** developer, **I want** documented runbooks for all key operational scenarios, **so that** I can respond to incidents efficiently without relying on memory.

**SP:** 5 | **Sprint:** 10 | **Deps:** All preceding epics

**AC:**
- [ ] `docs/runbooks/01-solace-disconnect-recovery.md`
- [ ] `docs/runbooks/02-rds-failover-recovery.md`
- [ ] `docs/runbooks/03-certificate-rotation.md`
- [ ] `docs/runbooks/04-new-destination-onboarding.md` (how to add a new Solace destination with zero code change)
- [ ] `docs/runbooks/05-dlq-message-replay.md` (how to replay from SQS DLQ and from Solace DMQ)
- [ ] `docs/runbooks/06-rosa-cluster-upgrade.md`
- [ ] Each runbook: symptoms, detection (CloudWatch alarm), immediate action, root cause investigation, recovery steps, verification, escalation path

---

### US-E13-003: Production go-live checklist
**As a** developer, **I want** a production go-live checklist completed before the first production deployment, **so that** nothing is missed.

**SP:** 2 | **Sprint:** 10 | **Deps:** US-E13-002

**AC:**
- [ ] All `Must` requirements from requirements.md are implemented and tested
- [ ] All CloudWatch Alarms in `OK` state at rest
- [ ] Security Hub enabled, CIS benchmark findings reviewed
- [ ] GuardDuty enabled
- [ ] All AWS resources tagged (Project, Environment, Owner, CostCenter, Destination)
- [ ] All NAT Gateway EIPs documented and shared with customer Solace ops team
- [ ] mTLS certificate expiry monitored (alarm set, rotation procedure documented)
- [ ] DR runbook executed at least once
- [ ] Load test results reviewed and approved
- [ ] Terraform state in S3 with locking; no local state files
- [ ] No secrets in Git (scan with `trufflehog` or `git-secrets`)

---

## Sprint Summary

| Sprint | Points | Epics | Key Milestone |
|---|---|---|---|
| 1 | 34 | E0, E1 (partial) | Local Docker Compose stack working; Terraform foundation |
| 2 | 32 | E1 (complete), E2 (partial), E3 (partial) | VPC + VPC Endpoints + ROSA provisioned; RDS running |
| 3 | 33 | E2 (complete), E3 (complete), E4, E5 (partial) | Security baseline done; SNS/SQS ready; App connects to Solace locally with mTLS |
| 4 | 33 | E5 (complete), E6 (partial) | Full message received, audit+outbox written, ACK sent — local end-to-end works |
| 5 | 32 | E6 (complete), E7, E8 (partial) | SNS publish from outbox works; claim-check works; circuit breakers in place |
| 6 | 33 | E8 (complete), E9 (partial) | Graceful shutdown + DLQ routing; App deployed to ROSA staging |
| 7 | 33 | E9 (complete), E10 (partial) | KEDA scaling works; ADOT + CloudWatch metrics + alarms live |
| 8 | 33 | E10 (complete), E11 | Dashboard live; full CI/CD pipeline running |
| 9 | 32 | E12, E13 (partial) | All load tests pass; Multi-AZ DR validated |
| 10 | 17 | E13 (complete) | Runbooks done; go-live checklist complete; **Production ready** |

**Total: ~306 story points across 10 sprints (20 weeks)**
