# CAG Hermes - Solace Messaging Middleware Integration with AWS

## Detailed Requirements Specification

| Field | Value |
|-------|-------|
| **Document Version** | 4.0 |
| **Date** | March 18, 2026 |
| **Status** | Revised Draft |
| **Classification** | Internal |
| **Previous Version** | 3.0 (March 18, 2026) |

---

## Revision History

| Version | Date | Change Summary |
|---------|------|---------------|
| 1.0 | 2026-03-18 | Initial draft |
| 2.0 | 2026-03-18 | Architecture review remediation: SNS/SQS migrated to FIFO; committed to ECS Fargate and PostgreSQL; fixed delivery semantics language; removed in-memory buffering; added VPC endpoints; fixed Solace ack timing; added multi-destination consumer model; resolved 27 review findings |
| 3.0 | 2026-03-18 | Container platform migrated from ECS Fargate to **Red Hat OpenShift on AWS (ROSA)**. Updated compute, IAM (STS/IRSA), scaling (HPA/KEDA), logging (ADOT to CloudWatch), secrets (External Secrets Operator), deployment (Helm), networking (NetworkPolicies), and security (SCCs) throughout. AWS-native observability (CloudWatch, X-Ray) retained. Amazon ECR retained for image registry |
| 4.0 | 2026-03-18 | Solace platform architecture review remediation: Added Section 3.8 (broker-side provisioning — queues, client profiles, ACL profiles, topic-to-queue subscriptions). Committed to JCSMP via Solace Spring Boot Starter (removed JMS/Binder ambiguity). Fixed reconnection to fixed-interval with `reconnectRetries: -1`. Reduced prefetch from 256 to 32. Specified `INDIVIDUAL_ACKNOWLEDGE` mode. Added transport buffer tuning, message compression, queue spool limits/TTL, SEMP v2 monitoring spec, client name collision fix, broker version requirements, message replay, and competing consumer ordering documentation. Resolved 19 Solace review findings (1 CRITICAL, 6 HIGH, 12 MEDIUM) |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Solution Overview](#2-solution-overview)
3. [Solace Messaging Middleware Integration Requirements](#3-solace-messaging-middleware-integration-requirements) *(includes 3.8 Broker-Side Provisioning)*
4. [Security Requirements](#4-security-requirements)
5. [Container and Compute Requirements](#5-container-and-compute-requirements)
6. [Database Requirements (Amazon RDS)](#6-database-requirements-amazon-rds)
7. [SNS/SQS Fan-out Pattern Requirements](#7-snssqs-fan-out-pattern-requirements)
8. [Disaster Recovery and Business Continuity](#8-disaster-recovery-and-business-continuity)
9. [Performance and Throughput Requirements](#9-performance-and-throughput-requirements)
10. [Load Testing Requirements](#10-load-testing-requirements)
11. [Monitoring and Observability](#11-monitoring-and-observability)
12. [Middleware Patterns and Best Practices](#12-middleware-patterns-and-best-practices)
13. [AWS Well-Architected Framework Alignment](#13-aws-well-architected-framework-alignment)
14. [Infrastructure as Code Requirements](#14-infrastructure-as-code-requirements)
15. [CI/CD Pipeline Requirements](#15-cicd-pipeline-requirements)
16. [Non-Functional Requirements Summary](#16-non-functional-requirements-summary)
17. [Glossary](#17-glossary)
18. [Appendices](#18-appendices)

---

## 1. Executive Summary

This document defines the detailed requirements for integrating a **Solace PubSub+ Messaging Middleware** infrastructure with AWS cloud services. The solution enables a Java/Spring Boot containerized application running on **Red Hat OpenShift Service on AWS (ROSA)** within an AWS VPC to securely connect to external Solace Messaging Middleware destinations over the public internet using TLS 1.2 with mutual certificate authentication.

The application supports **multiple distinct Solace destinations** (topics and queues), with dedicated OpenShift Deployments subscribing to each destination. Subscribed messages are audited in **Amazon RDS for PostgreSQL** with full transactional integrity, then published to **Amazon SNS FIFO topics** for fan-out distribution to multiple **Amazon SQS FIFO queues** for downstream processing. The architecture uses SNS/SQS FIFO to provide server-side message deduplication within a 5-minute window, combined with idempotent consumers at each stage for **effectively exactly-once processing semantics**.

The architecture adheres to all six pillars of the **AWS Well-Architected Framework** and incorporates enterprise-grade middleware patterns for reliability, security, and performance.

### Key Objectives

- Establish secure, resilient connectivity from AWS VPC to external Solace PubSub+ broker over TLS 1.2 via JCSMP API
- Support multiple distinct Solace destinations with independently scalable consumer groups on ROSA
- Implement transactional message processing with full audit trail in Amazon RDS for PostgreSQL
- Enable scalable fan-out distribution via SNS FIFO / SQS FIFO pattern for downstream consumers
- Ensure zero message loss with effectively exactly-once processing via FIFO deduplication and idempotent consumers
- Meet enterprise security, compliance, and operational excellence standards
- Leverage OpenShift platform capabilities (Operators, Helm, HPA/KEDA, SCCs) for enterprise-grade container orchestration

---

## 2. Solution Overview

### 2.1 Architecture Context

- Client-side application runs in an **AWS VPC** (private subnets) on a **ROSA cluster**
- **Solace PubSub+ Messaging Middleware** is external (hosted outside AWS)
- Communication traverses the **public internet over TLS 1.2** with certificate-based authentication
- Application is **containerized** using Java 17+ and Spring Boot 3.x, deployed as **OpenShift Deployments** on ROSA
- Application subscribes to **multiple distinct Solace destinations** (topics/queues), each handled by a dedicated OpenShift Deployment
- Message flow: **Solace Topic/Queue -> Java Consumer -> RDS Audit + Outbox (single TX) -> Solace ACK -> Outbox Poller -> SNS FIFO -> SQS FIFO Fan-out**

### 2.2 ROSA Platform Overview

| Aspect | Detail |
|--------|--------|
| **Platform** | Red Hat OpenShift Service on AWS (ROSA) — AWS-managed, jointly supported by Red Hat and AWS |
| **Cluster Version** | OpenShift 4.14+ (Kubernetes 1.27+) |
| **Worker Nodes** | EC2 instances in private subnets across multiple AZs (managed machine pools) |
| **IAM Integration** | ROSA with STS (Security Token Service) — pods assume IAM roles via IRSA (IAM Roles for Service Accounts) |
| **Networking** | OVN-Kubernetes CNI within the cluster; VPC networking for AWS service access |
| **Registry** | Amazon ECR (external) with image pull secrets |
| **Secrets** | External Secrets Operator (ESO) syncing from AWS Secrets Manager to Kubernetes Secrets |
| **Observability** | AWS-native: CloudWatch (metrics + logs via ADOT Collector), X-Ray (tracing via ADOT) |

### 2.3 Multi-Destination Consumer Model

The application supports subscribing to **N distinct Solace destinations** simultaneously. Each destination is served by a dedicated **OpenShift Deployment** within a shared namespace (or separate namespaces for stronger isolation), with independent scaling, configuration, and monitoring.

| Concept | Description |
|---------|-------------|
| **Destination** | A distinct Solace topic subscription or queue binding (e.g., `orders/events`, `inventory/updates`) |
| **Consumer Group** | A set of pods (replicas of a Deployment) consuming from the same Solace destination (competing consumers) |
| **Routing Rule** | Configuration mapping each Solace destination to a target SNS FIFO topic |
| **Scaling Independence** | Each consumer group auto-scales independently via its own HPA/KEDA scaler |

**REQ-ARCH-001:** Each Solace destination SHALL be served by a dedicated OpenShift Deployment, enabling independent scaling, deployment, and failure isolation.

**REQ-ARCH-002:** Destination-to-SNS-topic routing SHALL be configurable via externalized configuration (Kubernetes ConfigMaps backed by AWS Systems Manager Parameter Store via External Secrets Operator), allowing new destinations to be added without code changes.

**REQ-ARCH-003:** Each consumer group SHALL share a common container image with destination-specific configuration injected at runtime via environment variables from ConfigMaps and Secrets.

### 2.4 Key Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Messaging Middleware | Solace PubSub+ | Source message broker (external) |
| Application Runtime | Java 17+ / Spring Boot 3.x with Solace Spring Boot Starter (JCSMP) | Consumer application |
| Container Platform | Red Hat OpenShift on AWS (ROSA) | Enterprise Kubernetes container orchestration |
| Worker Nodes | EC2 instances (managed machine pools) | Compute capacity for pods |
| Database | Amazon RDS for PostgreSQL 15+ | Audit and transaction log |
| Notification Service | Amazon SNS (FIFO) | Message fan-out hub with deduplication |
| Queue Service | Amazon SQS (FIFO) | Downstream consumption queues with exactly-once delivery |
| Certificate Management | AWS Secrets Manager + External Secrets Operator | TLS certificate and keystore storage, synced to K8s Secrets |
| Secret Storage | AWS Secrets Manager + External Secrets Operator | Solace credentials, DB credentials synced to K8s Secrets |
| Configuration | AWS Systems Manager Parameter Store + ConfigMaps | Externalized application and destination configuration |
| Monitoring | Amazon CloudWatch + AWS Distro for OpenTelemetry (ADOT) | Metrics and logs shipped to CloudWatch |
| Tracing | AWS X-Ray via ADOT Collector | Distributed tracing |
| Networking | VPC, NAT Gateway, VPC Endpoints, OVN-Kubernetes, NetworkPolicies | Secure network connectivity |
| Auto-Scaling | Horizontal Pod Autoscaler (HPA) + KEDA | Pod-level and custom-metric-based scaling |
| Cluster Scaling | ROSA Cluster Autoscaler | Node-level scaling for worker pools |
| Package Management | Helm Charts | Application deployment and configuration templating |

### 2.5 High-Level Data Flow

```
                        Internet (TLS 1.2)
                              |
  +---------------------------+---------------------------+
  |                    AWS VPC (Private Subnets)           |
  |                                                        |
  |  +--------------------------------------------------+  |
  |  |               ROSA Cluster                       |  |
  |  |                                                  |  |
  |  |  +--------------------------------------------+  |  |
  |  |  | Namespace: hermes                          |  |  |
  |  |  |                                            |  |  |
  |  |  | Deployment: hermes-orders (N replicas)     |  |  |
  |  |  | Deployment: hermes-inventory (M replicas)  |  |  |
  |  |  | Deployment: hermes-payments (P replicas)   |  |  |
  |  |  |   (one Deployment per Solace destination)  |  |  |
  |  |  |                                            |  |  |
  |  |  |  1. Connect to Solace PubSub+ via JCSMP API |  |  |
  |  |  |  2. Subscribe to configured destination    |  |  |
  |  |  |  3. On message: open DB transaction        |  |  |
  |  |  |  4. Persist audit record + outbox (1 TX)   |  |  |
  |  |  |  5. Commit transaction                     |  |  |
  |  |  |  6. Acknowledge message to Solace          |  |  |
  |  |  |  7. Outbox poller publishes to SNS FIFO    |  |  |
  |  |  |  8. SNS FIFO fans out to SQS FIFO queues  |  |  |
  |  |  +--------------------------------------------+  |  |
  |  |  | ADOT Collector (DaemonSet)                 |  |  |
  |  |  |   -> CloudWatch Metrics & Logs             |  |  |
  |  |  |   -> X-Ray Traces                          |  |  |
  |  |  +--------------------------------------------+  |  |
  |  |  | External Secrets Operator                  |  |  |
  |  |  |   -> Syncs from Secrets Manager / SSM      |  |  |
  |  |  +--------------------------------------------+  |  |
  |  +--------------------------------------------------+  |
  |       |              |                |                 |
  |  +--------+   +------------+   +----------------+      |
  |  | RDS PG |   | SNS FIFO   |   | SQS FIFO       |     |
  |  | (Audit)|   | (Fanout)   |   | (Consumers)    |     |
  |  +--------+   +------------+   +----------------+      |
  |                                                        |
  |  VPC Endpoints: SNS, SQS, Secrets Manager, SSM,       |
  |  CloudWatch, X-Ray, KMS, ECR, S3                       |
  +--------------------------------------------------------+
```

**Detailed Flow Steps:**

1. Spring Boot application (running as a pod on ROSA) connects to Solace PubSub+ broker via **JCSMP API** (via Solace Spring Boot Starter) over TLS 1.2
2. Application subscribes to its configured Solace destination (topic or queue)
3. On message receipt, a database transaction is opened in RDS PostgreSQL
4. Message metadata and payload are persisted to the audit table
5. Message is written to the outbox table (within the same DB transaction)
6. Transaction is committed
7. Solace message is acknowledged immediately after successful DB commit
8. Outbox poller reads pending messages (via PostgreSQL `LISTEN/NOTIFY` for near-real-time triggering, with fallback polling every 500ms) and publishes to SNS FIFO with `MessageDeduplicationId` and `MessageGroupId`
9. SNS FIFO fans out the message to subscribed SQS FIFO queues
10. Downstream consumers process messages from SQS FIFO queues independently with exactly-once delivery per deduplication window

> **Note on delivery guarantees:** This architecture provides **effectively exactly-once processing** through three complementary mechanisms: (1) SNS FIFO / SQS FIFO server-side deduplication within a 5-minute window, (2) transactional outbox pattern ensuring at-least-once delivery from DB to SNS, and (3) idempotent consumers at each stage using the Solace message ID. All downstream consumers MUST implement idempotency as a defense-in-depth measure, since deduplication windows are finite and edge cases (e.g., outbox replay after dedup window expiry) can produce duplicates.

---

## 3. Solace Messaging Middleware Integration Requirements

### 3.1 Connection Requirements

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-001 | Application SHALL connect to Solace PubSub+ broker using the **Solace JCSMP API** (`com.solace:sol-jcsmp` version 10.21+) via the **Solace Spring Boot Starter** (`solace-spring-boot-starter`). JCSMP is chosen over JMS and Spring Cloud Stream Binder for: (a) full control over per-message ack timing required by the transactional outbox pattern, (b) direct flow receiver lifecycle management for backpressure, (c) highest performance via native SMF protocol, (d) fine-grained reconnection control via `SessionEventHandler`. The Solace JMS API and Spring Cloud Stream Solace Binder SHALL NOT be used | Must |
| REQ-SOL-002 | Connection SHALL use TLS 1.2 as the minimum protocol version; TLS 1.0 and 1.1 SHALL be disabled | Must |
| REQ-SOL-003 | Connection endpoint SHALL be configurable via externalized configuration (Kubernetes ConfigMaps sourced from AWS Systems Manager Parameter Store via External Secrets Operator) | Must |

**REQ-SOL-004:** The following Solace connection properties SHALL be configurable per destination:

| Property | Description | Example |
|----------|-------------|---------|
| `host` | Solace broker endpoint (SMF over TLS) | `tcps://broker.example.com:55443` |
| `vpn-name` | Solace Message VPN | `prod-vpn` |
| `username` | Client username | `aws-consumer` |
| `password` | Client password (stored in Secrets Manager, synced via ESO) | *(K8s Secret reference)* |
| `client-name` | Unique client identifier (includes pod UID to prevent name collisions during rolling updates — see note below) | `aws-hermes-{destination}-{pod-uid}` |
| `connect-retries` | Retries for the **initial** connection before giving up | `5` |
| `reconnect-retries` | Retries when an **established** session is lost. **-1 = infinite** (CRITICAL for production — default of 3 gives only 9-second tolerance) | `-1` |
| `reconnect-retry-wait-ms` | Fixed wait time between reconnect attempts (ms) | `3000` |
| `connect-timeout-ms` | Connection timeout (ms) | `30000` |
| `keep-alive-interval-ms` | Keep-alive interval (ms) | `3000` |
| `keep-alive-limit` | Missed keepalives before session declared dead (default 3). Increase for WAN tolerance | `5` |
| `compression-level` | JCSMP message compression level (0=off, 1-9=on). Reduces WAN bandwidth for JSON payloads by 60-80% | `6` |
| `sub-ack-window-size` | Guaranteed message ack window — controls how many messages broker sends before waiting for ack. Align with prefetch | `32` |
| `socket-receive-buffer-size` | TCP receive buffer size (bytes). Increase for WAN throughput | `131072` |
| `socket-send-buffer-size` | TCP send buffer size (bytes) | `65536` |
| `reapply-subscriptions` | Re-subscribe to topics after reconnection | `true` |
| `generate-sequence-numbers` | Enable for message ordering verification | `true` |
| `destination-name` | Solace topic or queue to subscribe to | `orders/events` |
| `destination-type` | `TOPIC` or `QUEUE` | `QUEUE` |
| `target-sns-topic-arn` | SNS FIFO topic ARN for this destination's output | `arn:aws:sns:...:hermes-orders.fifo` |

### 3.2 Solace Session Management

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-005 | Application SHALL use JCSMP's built-in **fixed-interval reconnection** with `reconnectRetries: -1` (infinite) and `reconnectRetryWaitInMillis: 3000` (3-second fixed interval). JCSMP does not natively support exponential backoff; the fixed-interval approach is the standard production pattern and is reliable. A `SessionEventHandler` SHALL log all reconnection lifecycle events (`SESSION_DOWN`, `RECONNECTING`, `RECONNECTED`). Note: `connectRetries` (initial connection) and `reconnectRetries` (reconnection after session loss) are separate JCSMP properties with different defaults | Must |
| REQ-SOL-006 | Application SHALL support Solace Guaranteed Messaging (persistent and non-persistent modes) | Must |
| REQ-SOL-007 | Application SHALL use **`SUPPORTED_MESSAGE_ACK_CLIENT_INDIVIDUAL`** (individual client acknowledgment) mode for guaranteed delivery — not `CLIENT_ACK` (cumulative) and not auto-ack. With 16 concurrent processing threads (REQ-PERF-006), cumulative `CLIENT_ACK` would implicitly acknowledge unprocessed messages when a later message is acked, risking silent message loss on pod crash. `INDIVIDUAL_ACKNOWLEDGE` ensures each message is independently acked only after its DB transaction commits | Must |
| REQ-SOL-008 | Application SHALL implement a Solace session event handler to capture and log connection lifecycle events (UP, DOWN, RECONNECTING, RECONNECTED) | Must |
| REQ-SOL-009 | Application SHALL support topic subscriptions and queue bindings as configurable parameters per destination | Must |
| REQ-SOL-010 | Application SHALL implement flow control to prevent message loss during high-throughput periods | Must |

### 3.3 Solace Connection Capacity

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-020 | Maximum concurrent Solace connections SHALL be documented and agreed with the Solace operations team prior to deployment | Must |
| REQ-SOL-021 | The Solace Message VPN connection limit SHALL accommodate the maximum total pods across all consumer groups (sum of all destination max replica counts) | Must |
| REQ-SOL-022 | Connection capacity SHALL be validated during scaling load tests to ensure Solace broker licensing supports the maximum concurrent connections | Must |

### 3.4 Spring Boot Integration

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-011 | Application SHALL use the **Solace Spring Boot Starter** (`solace-spring-boot-starter`) for direct JCSMP integration with Spring Boot auto-configuration. Spring Cloud Stream Solace Binder SHALL NOT be used — the binder's managed ack lifecycle, error channel interference with Resilience4j retries, and limited control over flow receiver lifecycle conflict with the transactional outbox pattern's requirements for explicit per-message ack timing and backpressure control | Must |
| REQ-SOL-012 | Application SHALL use **JCSMP `FlowReceiver`** for message consumption, providing direct control over: (a) per-message `INDIVIDUAL_ACKNOWLEDGE`, (b) flow start/stop for backpressure, (c) `XMLMessageListener` for async message receipt, (d) `FlowEventHandler` for flow lifecycle events | Must |
| REQ-SOL-013 | Application SHALL externalize all Solace configuration via Spring profiles (`application-{env}.yml`) with per-destination overrides injected from Kubernetes ConfigMaps | Must |
| REQ-SOL-014 | Application SHALL implement health indicators for Solace connection status integrated with Spring Boot Actuator (`/actuator/health`), exposed via Kubernetes readiness probes. Readiness probe SHALL fail when the Solace session is down, removing the pod from the Kubernetes Service | Must |

### 3.5 Message Processing

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-015 | Application SHALL deserialize incoming Solace messages into a canonical data model (POJO/DTO) | Must |
| REQ-SOL-016 | Application SHALL validate incoming message schema before processing (JSON Schema or Bean Validation), including a **maximum payload size check of 200 KB** to ensure compatibility with SNS/SQS FIFO limits (256 KB including attributes and overhead) | Must |
| REQ-SOL-017 | Application SHALL implement idempotent message processing using a unique message identifier (Solace message ID or application-defined correlation ID) stored in the audit table | Must |
| REQ-SOL-018 | Application SHALL implement a dead-letter queue (DLQ) strategy for messages that fail processing after configurable retry attempts (default: 3). The Solace-side Dead Message Queue (DMQ) SHALL also be configured with a matching max-redelivery count (see REQ-SOL-023) | Must |
| REQ-SOL-019 | Application SHALL log message receipt, processing start, processing completion, and any errors with correlation IDs | Must |

### 3.6 Message Size and Claim-Check

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-024 | Maximum expected message payload size SHALL be **200 KB** (to fit within the 256 KB SNS/SQS FIFO message limit after accounting for message attributes and protocol overhead) | Must |
| REQ-SOL-025 | For messages exceeding 200 KB, the application SHALL implement the **Claim-Check Pattern**: store the full payload in Amazon S3, and publish only a reference (S3 URI + metadata) to the outbox/SNS | Should |
| REQ-SOL-026 | If the Claim-Check Pattern is used, the S3 bucket SHALL use encryption at rest (KMS CMK), lifecycle policies, and the SQS Extended Client Library SHOULD be used by downstream consumers | Should |

### 3.7 Solace-Side Dead Message Queue (DMQ)

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-023 | Solace DMQ (Dead Message Queue) SHALL be configured for each subscribed queue with `max-redelivery-count` aligned to the application retry count (default: 3) | Must |
| REQ-SOL-027 | Solace DMQ depth SHALL be monitored via SEMP API and published as a custom CloudWatch metric (`solace.dmq.depth` per destination) via the ADOT Collector | Must |
| REQ-SOL-028 | CloudWatch Alarm SHALL trigger immediately (Critical severity) when Solace DMQ depth > 0 | Must |
| REQ-SOL-029 | Coordination with the Solace operations team SHALL be documented, including: DMQ configuration, max-redelivery settings, connection limits, and EIP whitelisting procedures | Must |

### 3.8 Solace Broker-Side Provisioning Requirements

> **Context:** The requirements in Sections 3.1–3.7 are consumer-side (application) specifications. This section specifies the **broker-side** objects that must be provisioned by the Solace operations team before the consumer application can connect. Without these, the application cannot be deployed.

#### 3.8.1 Solace Broker Version and Edition

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-030 | Solace PubSub+ broker SHALL be **version 10.2+** (minimum). The deployment model (Software Broker, Appliance, or Solace Cloud) SHALL be documented | Must |
| REQ-SOL-031 | Solace PubSub+ **Enterprise edition** is RECOMMENDED for: Message Replay, OAuth authentication, and higher spool limits. If Standard edition is used, document which Enterprise-only features are unavailable | Should |
| REQ-SOL-032 | The Solace broker's **HA configuration** SHALL be documented: Active/Standby redundancy pair, standalone, or Solace Cloud (managed HA). If HA is configured, the JCSMP `host` property SHALL use a comma-separated host list for automatic client failover (e.g., `tcps://primary:55443,tcps://standby:55443`) | Must |

#### 3.8.2 Queue Provisioning (Per Destination)

**REQ-SOL-033:** A Solace queue SHALL be provisioned for each destination with the following configuration:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Queue Name | `hermes.{destination-name}` | e.g., `hermes.orders`, `hermes.inventory` |
| Access Type | **Non-Exclusive** | For competing consumers. Use **Exclusive** only for destinations requiring strict global ordering (see REQ-PAT-009) |
| Owner | `hermes-client-username` | The client username used by the application |
| Permission | Consume | Consumer-only; no publish permission to this queue |
| Max Spool Usage | **4 GB** per queue (configurable per destination) | Sized for ~6 min buffering at 1,000 msgs/s x 10 KB avg |
| Max Message Count | **1,000,000** per queue | Safety limit to prevent unbounded growth |
| Max Redelivery Count | **10** | Set higher than app retry count (3) to account for redeliveries caused by pod crashes during prefetch — Solace increments the redelivery counter each time a message is dispatched, including to the prefetch buffer |
| Max Message Size | **256,000 bytes** | Matches SNS FIFO message limit |
| Respect TTL | **Enabled** | Honor message TTL on this queue |
| Message TTL | **86,400,000 ms** (24 hours) | Configurable per destination. Discard stale messages from prolonged consumer outages |
| Reject Msg to Sender on Discard | **Yes** | Publisher receives NACK when queue is full — provides backpressure to the publishing system |
| Dead Message Queue | `#DEAD_MSG_QUEUE` (VPN-level DMQ) or `hermes.{destination}.dmq` (per-queue DMQ) | Align with REQ-SOL-023 |
| Consumer Ack Propagation | **Enabled** | Propagate acks from consumers to the queue |

#### 3.8.3 Topic-to-Queue Subscription Mapping

**REQ-SOL-034:** For **topic-based destinations**, topic endpoint subscriptions SHALL be added to the queue on the Solace broker to attract and spool messages published to matching topics:

| Parameter | Description | Example |
|-----------|-------------|---------|
| Queue Name | Target queue for spooled messages | `hermes.orders` |
| Topic Subscription | Topic string (including Solace wildcards `*` and `>`) | `orders/events/>` |
| Subscription Type | **Durable** (persists across broker restarts) | Durable |
| Managed By | Solace operations team (static provisioning) or application via JCSMP `addSubscription()` | Solace ops (recommended for production) |

**REQ-SOL-035:** Each destination SHALL be documented with:

| Field | Description | Example |
|-------|-------------|---------|
| Destination Name | Logical name | `orders` |
| Destination Type | `QUEUE` (direct queue binding) or `TOPIC` (topic-to-queue subscription) | `TOPIC` |
| Solace Queue Name | Broker-side queue name | `hermes.orders` |
| Topic Subscription(s) | Topic filter strings (if topic-based). Wildcards: `*` = single level, `>` = multi-level | `orders/events/>`, `orders/commands/*` |
| Access Type | Exclusive or Non-Exclusive | Non-Exclusive |
| Ordering Requirement | None, per-correlation-group, or strict global | Per-correlation-group |
| Ordering Note | For **non-exclusive queues** with competing consumers, message ordering is NOT preserved across consumers. Solace round-robins messages across connected consumers. If ordering within a correlation group is required (e.g., all events for order #12345 in sequence), use SNS FIFO `MessageGroupId` keyed on the correlation ID — ordering is enforced per message group on the SQS FIFO side. Solace **partitioned queues** (v10.2+) SHOULD be evaluated for Solace-side per-key ordering | — |

> **Competing consumer ordering note (REQ-PAT-003):** With non-exclusive queues and N pod replicas, Solace distributes messages round-robin across consumers. This means: (a) message ordering across consumers is not preserved, (b) when a consumer disconnects, its unacknowledged messages are redelivered to other consumers with the `redelivered` flag set, (c) the application's idempotent consumer (REQ-PAT-001) SHALL check the redelivered flag and handle accordingly. For destinations requiring strict per-key ordering on the Solace side, evaluate Solace partitioned queues.

#### 3.8.4 Client Profile

**REQ-SOL-036:** A Solace client profile SHALL be provisioned for the hermes application:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Profile Name | `hermes-client-profile` | |
| Max Connections per Client Username | **100** | Must accommodate maximum total pods across all destinations (sum of all max replica counts) |
| Allow Guaranteed Message Receive | **Yes** | Consumer application |
| Allow Guaranteed Message Send | **No** | Consumer-only; no publishing to Solace |
| Max Egress Flows | **50** | Per-connection egress flows |
| Max Endpoints per Client | **10** | |
| Max Outstanding Unacked Messages | **64** | Set to prefetch x 2 (32 x 2 = 64). Controls when the broker stops delivering messages to a slow consumer — this is Solace's native flow control mechanism. Align with application-level backpressure (REQ-PAT-008) |
| Compression | **Enabled** | Required for message compression (REQ-SOL-004 `compression-level`) |
| Reject Duplicate Client Name | **Yes** | Prevents connection conflicts. Client name uses pod UID (REQ-SOL-004) to avoid collisions during rolling updates |
| TCP Window Size (Subscriber) | **131072** bytes | Aligned with JCSMP `socket-receive-buffer-size` for WAN throughput |

#### 3.8.5 ACL Profile

**REQ-SOL-037:** A Solace ACL profile SHALL be provisioned for the hermes application:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Profile Name | `hermes-acl-profile` | |
| Client Connect Default | **Allow** | Allow connections from hermes client username |
| Subscribe Topic Default | **Deny** | Deny all topic subscriptions by default |
| Subscribe Topic Exceptions (Allow) | Per-destination topic subscriptions (e.g., `orders/events/>`, `inventory/updates/*`) | Whitelist only the topics the application needs |
| Publish Topic Default | **Deny** | Consumer-only — no publishing |

#### 3.8.6 Client Username

**REQ-SOL-038:** A Solace client username SHALL be provisioned:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Client Username | `hermes-aws-consumer` | |
| Client Profile | `hermes-client-profile` | |
| ACL Profile | `hermes-acl-profile` | |
| Authentication | Per REQ-SOL-039 (see below) | |
| Guaranteed Endpoint Permission | **Consume** | Allow binding to provisioned queues |

#### 3.8.7 Authentication Method

**REQ-SOL-039:** Solace authentication SHALL be confirmed with the Solace operations team. The preferred priority order is:

| Priority | Method | Security Level | Implementation |
|----------|--------|---------------|----------------|
| 1 (Preferred) | **Client Certificate (mTLS)** | Highest | Certificate CN mapped to client username. If the Solace broker supports mTLS, REQ-SEC-003 is elevated to **Must** and username/password is removed |
| 2 | **OAuth 2.0 (JWT)** | High | Token-based authentication with automatic token refresh. Requires Solace Enterprise edition |
| 3 (Fallback) | **Basic (username/password)** | Adequate with TLS | Password stored in Secrets Manager with 90-day rotation (REQ-SEC-017). Acceptable for production over TLS 1.2 |

> **Decision required:** The chosen authentication method SHALL be documented and the broker-side client username configured accordingly. The decision depends on Solace broker capabilities and organizational security policy.

#### 3.8.8 SEMP API Monitoring Configuration

**REQ-SOL-040:** SEMP (Solace Element Management Protocol) monitoring SHALL be configured as follows:

| Parameter | Value | Notes |
|-----------|-------|-------|
| SEMP Version | **SEMPv2** (REST/JSON) | Modern REST API; avoid legacy SEMPv1 XML |
| SEMP Endpoint | Port **943** (SEMP over TLS) | Referenced in security groups (Appendix D) |
| SEMP User | Dedicated **read-only** monitoring user | Separate from the application client username |
| SEMP Credentials | Stored in **Secrets Manager** (separate secret from client credentials), synced via ESO | |
| SEMP Access Level | **Read-only** | Monitoring only; no management operations |
| Polling Interval | **30 seconds** | For DMQ depth, queue depth, connection count, spool usage |

**REQ-SOL-041:** The following SEMP metrics SHALL be monitored and published as CloudWatch custom metrics under the `CAGHermes/Solace` namespace (via the ADOT Collector or a dedicated monitoring sidecar):

| SEMP Metric | CloudWatch Metric Name | Alarm Threshold | Severity |
|-------------|----------------------|-----------------|----------|
| Queue spool usage (bytes) | `solace.queue.spool.usage` | > 80% of max spool | High |
| Queue message count | `solace.queue.message.count` | > 500,000 | Medium |
| Queue bind count (consumers) | `solace.queue.bind.count` | = 0 (no consumers) | Critical |
| Queue discard count | `solace.queue.discard.count` | > 0 | Critical |
| Queue average egress rate | `solace.queue.egress.rate` | Drop > 50% over 5 min | High |
| DMQ message count | `solace.dmq.depth` | > 0 (existing REQ-SOL-028) | Critical |
| Client connection count (per VPN) | `solace.vpn.connection.count` | > 80% of VPN limit | High |
| Redelivered message count | `solace.queue.redelivered.count` | > 100 per minute | Medium |

#### 3.8.9 Message Replay (If Enterprise Edition)

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-042 | If Solace PubSub+ **Enterprise edition** is available, **Message Replay** SHALL be enabled on all production queues. Replay log retention SHALL be configured for a minimum of **24 hours** | Should |
| REQ-SOL-043 | The **DR runbook** (REQ-DR-016) SHALL include a documented procedure for initiating message replay from a specific timestamp to recover from consumer processing failures, audit table corruption, or bug-related reprocessing needs | Should |
| REQ-SOL-044 | Message Replay provides an independent source of truth separate from the audit table. It SHALL be tested as part of the quarterly DR exercise (REQ-DR-016) | Should |

#### 3.8.10 Broker-Side Provisioning Coordination

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SOL-045 | A **Solace Provisioning Request** document SHALL be produced from this specification and shared with the Solace operations team. It SHALL include: all queue definitions, client profile, ACL profile, client username, topic-to-queue subscriptions, DMQ configuration, SEMP monitoring user, and all NAT Gateway EIPs for IP whitelisting | Must |
| REQ-SOL-046 | Provisioning SHALL be validated in a **non-production environment** before production deployment. Validation includes: successful client connection, topic subscription message flow, queue depth monitoring, DMQ routing on max-redelivery, and SEMP metric collection | Must |

---

## 4. Security Requirements

### 4.1 Transport Security

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-001 | All communication between the ROSA cluster and Solace broker SHALL use TLS 1.2 with strong cipher suites (`TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`, `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`) | Must |
| REQ-SEC-002 | Server certificate validation SHALL be enforced; the Solace broker's CA certificate SHALL be trusted in the application's truststore | Must |
| REQ-SEC-003 | Client certificates (mutual TLS / mTLS) SHOULD be used if supported by the Solace infrastructure | Should |
| REQ-SEC-004 | Solace TLS certificates (client certs, truststore JKS/PKCS12, keystore) SHALL be stored in **AWS Secrets Manager** and synced to Kubernetes Secrets via the **External Secrets Operator (ESO)** with automatic rotation enabled and zero-downtime rotation. Note: AWS Certificate Manager (ACM) is NOT suitable for this use case as it does not allow private key export for application-level Java truststore/keystore usage | Must |
| REQ-SEC-005 | Certificate expiration monitoring SHALL alert at 30, 14, and 7 days before expiry via CloudWatch Alarms | Must |
| REQ-SEC-006 | Java truststore and keystore SHALL be mounted into pods as Kubernetes Secret volumes (synced from Secrets Manager via ESO). They SHALL NOT be baked into container images | Must |

### 4.2 Network Security

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-007 | ROSA worker nodes SHALL run in **private subnets** within the AWS VPC (no public IP assignment). The ROSA cluster API server SHOULD be private (PrivateLink-enabled) | Must |
| REQ-SEC-008 | Outbound connectivity from pods to Solace SHALL be via a **NAT Gateway** with Elastic IP for IP whitelisting on the Solace side. **All NAT Gateway EIPs across all AZs** SHALL be pre-registered with the Solace broker operations team | Must |
| REQ-SEC-009 | **OpenShift NetworkPolicies** SHALL restrict pod-to-pod traffic: only hermes application pods SHALL communicate with RDS, and egress SHALL be limited to Solace broker IPs, VPC Endpoint IPs, and RDS endpoints. Default-deny ingress and egress policies SHALL be applied to the hermes namespace | Must |
| REQ-SEC-010 | VPC-level Security Groups on ROSA worker nodes SHALL restrict outbound traffic to Solace broker IPs (55443, 943), RDS (5432), and VPC endpoints (443). NACLs SHALL provide an additional defense layer | Must |
| REQ-SEC-011 | VPC Flow Logs SHALL be enabled and stored in S3 with a **90-day** retention for network audit | Must |
| REQ-SEC-012 | **AWS Network Firewall** SHOULD be used for domain-based filtering on the outbound path (restricting to Solace broker FQDNs only) | Should |
| REQ-SEC-013 | **Route 53 Resolver Query Logging** SHALL be enabled for DNS audit logging of all DNS queries within the VPC | Must |
| REQ-SEC-014 | Inbound traffic from the internet to the application pods SHALL be blocked (no Routes or Ingress for the hermes application). Only the ROSA cluster API and OpenShift console require controlled inbound access | Must |

### 4.3 VPC Endpoints

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-035 | **S3 Gateway VPC Endpoint** SHALL be created (free, no hourly charge) for S3 access (logs, archives, backups, ECR image layers) | Must |
| REQ-SEC-036 | **Interface VPC Endpoints (PrivateLink)** SHALL be created for the following AWS services to keep traffic within the AWS network and eliminate NAT Gateway data processing charges for AWS API calls: SNS, SQS, Secrets Manager, SSM, CloudWatch Monitoring, CloudWatch Logs, X-Ray, KMS, ECR API, ECR DKR (Docker), STS | Must |
| REQ-SEC-037 | VPC Endpoint security groups SHALL restrict access to the ROSA worker node security groups | Must |
| REQ-SEC-038 | VPC Endpoint policies SHALL follow least-privilege, restricting access to only the specific resources used by the application | Should |

### 4.4 Identity and Access Management (IAM)

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-015 | Application pods SHALL use **ROSA STS with IAM Roles for Service Accounts (IRSA)** for all AWS service interactions. Each Kubernetes ServiceAccount used by hermes Deployments SHALL be annotated with an IAM role ARN. No long-term AWS credentials (access keys) SHALL be used | Must |
| REQ-SEC-016 | IAM policies SHALL follow **least-privilege** principle; separate policies for SNS publish, SQS send, RDS access, Secrets Manager read, CloudWatch write, and X-Ray write. A single IAM role per consumer group MAY be used if all destinations require the same permissions; otherwise, separate roles per destination | Must |
| REQ-SEC-017 | Solace credentials SHALL be stored in AWS Secrets Manager with automatic rotation enabled (90-day rotation policy), synced to Kubernetes Secrets via ESO | Must |
| REQ-SEC-018 | Secrets Manager resource policies SHALL restrict access to only the application's IAM roles (referenced via IRSA) | Must |
| REQ-SEC-019 | All IAM role assumptions (including STS AssumeRoleWithWebIdentity from IRSA) SHALL be logged via AWS CloudTrail | Must |
| REQ-SEC-020 | ROSA-managed service-linked roles SHALL be used for cluster operations | Should |
| REQ-SEC-039 | RDS access SHALL use **IAM database authentication** (`rds-db:connect` permission via IRSA) instead of static username/password where supported. If IAM auth is not feasible (e.g., connection pooling limitations with HikariCP), database credentials SHALL be stored in Secrets Manager with automatic rotation and synced via ESO | Must |

### 4.5 OpenShift Security

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-044 | Application pods SHALL run under a **restricted Security Context Constraint (SCC)** — the most restrictive SCC that permits the application to function. Pods SHALL NOT run as root, SHALL NOT request privileged mode, and SHALL drop all Linux capabilities except those explicitly required | Must |
| REQ-SEC-045 | The hermes namespace SHALL enforce **Pod Security Standards** at the `restricted` level via OpenShift's built-in admission controller | Must |
| REQ-SEC-046 | **RBAC (Role-Based Access Control)** SHALL be configured with least-privilege Roles and RoleBindings within the hermes namespace. The application ServiceAccount SHALL have no cluster-level permissions | Must |
| REQ-SEC-047 | OpenShift **image policy** SHALL restrict image sources to the approved Amazon ECR registry only for the hermes namespace | Must |
| REQ-SEC-048 | **Resource quotas** and **LimitRanges** SHALL be applied to the hermes namespace to prevent resource starvation of other workloads on the cluster | Must |

### 4.6 Data Security

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-021 | RDS database SHALL use **encryption at rest** via AWS KMS with a customer-managed key (CMK) | Must |
| REQ-SEC-022 | RDS connections SHALL use SSL/TLS with certificate verification enforced (`sslmode=verify-full`) | Must |
| REQ-SEC-023 | SNS FIFO topics SHALL use server-side encryption (SSE) with KMS CMK | Must |
| REQ-SEC-024 | SQS FIFO queues SHALL use server-side encryption (SSE-KMS with CMK) | Must |
| REQ-SEC-025 | Application logs SHALL NOT contain sensitive data (message payloads with PII, credentials); implement log masking/redaction | Must |
| REQ-SEC-026 | S3 buckets (for logs, backups, archives) SHALL enforce encryption, versioning, and block public access | Must |
| REQ-SEC-027 | KMS key policies SHALL follow separation of duties; key administrators SHALL NOT be key users | Must |
| REQ-SEC-028 | Database credentials SHALL be stored in Secrets Manager, rotated automatically, and synced to Kubernetes Secrets via ESO | Must |

### 4.7 Data Classification and PII Handling

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-040 | Message payload data classification SHALL be documented per Solace destination (e.g., Public, Internal, Confidential, Restricted) | Must |
| REQ-SEC-041 | If message payloads contain PII, the `message_payload` column in the audit table SHALL use **column-level encryption** (via `pgcrypto`) or store only a hash/reference with the full payload in an encrypted S3 object | Must |
| REQ-SEC-042 | Non-production environments SHALL use **data masking** for any PII fields in the audit table (synthetic or redacted data) | Must |
| REQ-SEC-043 | If GDPR/CCPA applies, the audit and archive data SHALL support **right-to-deletion** requests with a documented process for identifying and purging records by data subject identifier | Should |

### 4.8 Compliance and Governance

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-SEC-029 | AWS Config rules SHALL monitor security group changes, encryption status, and IAM policy modifications | Must |
| REQ-SEC-030 | AWS Security Hub SHALL be enabled with CIS AWS Foundations Benchmark | Must |
| REQ-SEC-031 | Amazon GuardDuty SHALL be enabled for threat detection | Must |
| REQ-SEC-032 | All API calls SHALL be logged via CloudTrail with log file integrity validation enabled and a **minimum 90-day retention** period | Must |
| REQ-SEC-033 | All AWS resources SHALL be tagged with standard tags: `Project`, `Environment`, `Owner`, `CostCenter`, `Compliance`, `Destination` (for per-destination resources). Kubernetes resources SHALL use equivalent labels | Must |
| REQ-SEC-034 | AWS CloudTrail logs SHALL be stored in S3 with **90-day** retention, matching VPC Flow Log retention | Must |

---

## 5. Container and Compute Requirements

### 5.1 ROSA Cluster Configuration

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-CMP-001 | Application SHALL be deployed on a **Red Hat OpenShift Service on AWS (ROSA)** cluster with STS enabled. Cluster version SHALL be OpenShift 4.14+ | Must |
| REQ-CMP-002 | ROSA cluster SHALL use **multi-AZ worker machine pools** spanning minimum 2 Availability Zones for high availability | Must |
| REQ-CMP-003 | Worker node instance type SHALL be **m6i.xlarge** minimum (4 vCPU, 16 GB RAM) for production. Non-production MAY use **m6i.large** (2 vCPU, 8 GB RAM) | Must |
| REQ-CMP-004 | **ROSA Cluster Autoscaler** SHALL be enabled to add/remove worker nodes based on pending pod demand. Minimum nodes: 3 (one per AZ). Maximum nodes: configurable (default: 12) | Must |
| REQ-CMP-005 | ROSA cluster SHALL be configured with a **private API server** (PrivateLink) where feasible. If public API is required for CI/CD access, API server allowlisting SHALL restrict access to known CIDR ranges | Should |
| REQ-CMP-006 | A dedicated **OpenShift namespace** (`hermes` or per-destination namespaces) SHALL be created for the application with appropriate ResourceQuotas and LimitRanges | Must |

### 5.2 Container Images

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-CMP-007 | Container images SHALL be stored in **Amazon ECR** with image scanning enabled (on push and periodic) | Must |
| REQ-CMP-008 | Container images SHALL use a **Red Hat Universal Base Image (UBI)** with Eclipse Temurin JRE 17 or Red Hat build of OpenJDK 17 to ensure compatibility with OpenShift SCCs and support entitlements | Must |
| REQ-CMP-009 | Container images SHALL NOT contain secrets, credentials, or environment-specific configuration | Must |
| REQ-CMP-010 | Container images SHALL be signed using Sigstore/cosign or Red Hat image signing for supply chain integrity | Should |
| REQ-CMP-011 | Multi-stage Docker builds SHALL be used to minimize image size | Must |
| REQ-CMP-012 | A single container image SHALL be shared across all consumer groups; destination-specific behavior SHALL be driven entirely by runtime configuration (ConfigMaps, Secrets, environment variables) | Must |
| REQ-CMP-013 | OpenShift **ImageStream** tags SHOULD be used to track deployed image versions and enable rollback | Should |
| REQ-CMP-014 | **Image pull secrets** for ECR SHALL be configured in the hermes namespace and referenced by the application ServiceAccount. ECR credential refresh SHALL be automated (via CronJob or ECR token refresh mechanism) | Must |

### 5.3 Pod / Deployment Configuration

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-CMP-015 | Each Solace destination SHALL be served by a dedicated **OpenShift Deployment** (not DeploymentConfig) with configurable replica count | Must |
| REQ-CMP-016 | Each pod SHALL request minimum **1 vCPU and 2 GB memory** with limits of **2 vCPU and 4 GB memory** (tunable per destination based on load testing) | Must |
| REQ-CMP-017 | JVM settings SHALL be configured for container awareness: `-XX:+UseContainerSupport`, `-XX:MaxRAMPercentage=75` | Must |
| REQ-CMP-018 | Kubernetes probes SHALL be configured: **livenessProbe** (JVM alive, HTTP GET `/actuator/health/liveness`), **readinessProbe** (Solace connected + RDS connected, HTTP GET `/actuator/health/readiness`), **startupProbe** (initial connection establishment, HTTP GET `/actuator/health` with `failureThreshold: 30`, `periodSeconds: 10`) | Must |
| REQ-CMP-019 | **Graceful shutdown** SHALL be implemented with `terminationGracePeriodSeconds: 60` and a `preStop` lifecycle hook to allow the application to: (a) stop accepting new messages from Solace, (b) complete in-flight processing, (c) flush pending outbox records owned by this instance, (d) cleanly disconnect from Solace. If outbox flush exceeds the drain timeout, orphaned records SHALL be picked up by other pods via `SELECT ... FOR UPDATE SKIP LOCKED` | Must |
| REQ-CMP-020 | Container logging SHALL use JSON structured format to stdout/stderr, collected by the ADOT Collector DaemonSet and shipped to CloudWatch Logs | Must |
| REQ-CMP-021 | `SIGTERM` handler SHALL stop accepting new messages from Solace, complete in-flight processing, flush outbox, and cleanly disconnect | Must |
| REQ-CMP-022 | **Pod anti-affinity rules** SHALL ensure pods of the same Deployment are distributed across different worker nodes and AZs (`topologySpreadConstraints` or `podAntiAffinity` with `topologyKey: topology.kubernetes.io/zone`) | Must |
| REQ-CMP-023 | **Pod Disruption Budgets (PDB)** SHALL be configured for each Deployment with `minAvailable: 1` (or `maxUnavailable: 1`) to ensure availability during node drains and cluster upgrades | Must |

### 5.4 Auto-Scaling (Per Destination)

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-CMP-024 | Each Deployment SHALL auto-scale independently using a **Horizontal Pod Autoscaler (HPA)** for CPU-based scaling | Must |
| REQ-CMP-025 | **KEDA (Kubernetes Event-Driven Autoscaler)** SHALL be installed on the ROSA cluster (via OperatorHub) and used for custom-metric-based scaling on: **outbox pending count** (`outbox.pending.count` from CloudWatch) and optionally Solace queue depth (via SEMP API) | Must |
| REQ-CMP-026 | Minimum replica count per destination SHALL be **2** (for high availability across AZs) | Must |
| REQ-CMP-027 | Maximum replica count per destination SHALL be configurable (default: **10**) | Must |
| REQ-CMP-028 | HPA scale-out policy: Add 1 pod when average CPU > 70% for 3 consecutive minutes | Must |
| REQ-CMP-029 | HPA scale-in policy: Remove 1 pod when average CPU < 30% for 10 minutes (with `stabilizationWindowSeconds: 300`) | Must |

> **Capacity note:** With a default max of 10 pods per destination and N destinations, the maximum total Solace connections = 10 x N. This must be validated against Solace Message VPN connection limits (see REQ-SOL-020/021). The ROSA Cluster Autoscaler will provision additional worker nodes as needed to accommodate pods.

### 5.5 Operational Access

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-CMP-030 | Spring Boot Actuator endpoints SHALL be exposed on a separate management port (e.g., 8081) for health, metrics, and info. These SHALL be used by Kubernetes probes and internal monitoring only | Must |
| REQ-CMP-031 | An internal **OpenShift Service** (ClusterIP type, no Route/Ingress) SHALL expose Actuator endpoints for monitoring tools within the cluster. No external access to the hermes application SHALL be provisioned | Must |

---

## 6. Database Requirements (Amazon RDS for PostgreSQL)

### 6.1 Database Configuration

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DB-001 | Database engine SHALL be **Amazon RDS for PostgreSQL 15+** | Must |
| REQ-DB-002 | Instance class SHALL be **db.r6g.large** minimum (production); **db.t3.medium** (non-production) | Must |
| REQ-DB-003 | Storage SHALL use **gp3** with provisioned IOPS based on load testing results (baseline: 3,000 IOPS, 125 MB/s throughput) | Must |
| REQ-DB-004 | **Multi-AZ deployment** SHALL be enabled for production environments | Must |
| REQ-DB-005 | Read replicas SHOULD be provisioned for reporting/analytics workloads (minimum 1 read replica in production) | Should |
| REQ-DB-006 | **RDS Proxy** SHOULD be used for connection pooling and improved failover performance. If used, `MaxConnectionsPercent` SHALL be set to accommodate maximum concurrent connections across all consumer groups (see Section 6.5 Capacity Planning) | Should |

### 6.2 Audit Schema Requirements

**REQ-DB-007:** An audit table SHALL capture the following fields:

| Column | Type | Description | Nullable |
|--------|------|-------------|----------|
| `id` | `BIGSERIAL` | Primary key | No |
| `message_id` | `VARCHAR(255) UNIQUE` | Solace message ID (for idempotency) | No |
| `correlation_id` | `VARCHAR(255)` | Business correlation identifier | Yes |
| `source_destination` | `VARCHAR(512)` | Solace source topic/queue name | No |
| `consumer_group` | `VARCHAR(255)` | Identifier of the consumer group (Deployment name) that processed this message | No |
| `message_payload` | `JSONB` | Full message payload (or S3 reference if claim-check is used) | Yes |
| `payload_size_bytes` | `INTEGER` | Size of original payload in bytes | No |
| `payload_hash` | `VARCHAR(64)` | SHA-256 hash of payload for integrity verification | Yes |
| `sns_message_id` | `VARCHAR(255)` | SNS publish message ID (populated after publish) | Yes |
| `sns_topic_arn` | `VARCHAR(512)` | Target SNS FIFO topic ARN | Yes |
| `status` | `VARCHAR(50)` | `RECEIVED`, `PROCESSING`, `PUBLISHED`, `FAILED`, `DLQ` | No |
| `retry_count` | `INTEGER` | Number of processing attempts | No (default 0) |
| `error_message` | `TEXT` | Error details if processing failed | Yes |
| `received_at` | `TIMESTAMP WITH TIME ZONE` | When message was received from Solace | No |
| `processed_at` | `TIMESTAMP WITH TIME ZONE` | When processing completed | Yes |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | Row creation timestamp | No |
| `updated_at` | `TIMESTAMP WITH TIME ZONE` | Last update timestamp | No |

### 6.3 Transaction Management

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DB-008 | Message processing SHALL follow the **Transactional Outbox Pattern**: audit record insert and outbox record insert SHALL be part of the same database transaction | Must |
| REQ-DB-009 | Application SHALL use Spring `@Transactional` with `REQUIRED` propagation and `READ_COMMITTED` isolation level | Must |
| REQ-DB-010 | Solace message acknowledgment SHALL occur **immediately after the database transaction is committed successfully** (not after outbox processing). This decouples the Solace consumer from the async outbox poller and avoids complex cross-thread coordination | Must |

> **Rationale for ack-at-commit (REQ-DB-010):** Once the message is durably written to the audit table and outbox within a committed transaction, the outbox pattern guarantees eventual delivery to SNS. Delaying the Solace ack until after SNS publish would require complex signaling between the async outbox poller and the consumer thread, introduce up to 500ms+ additional latency, and complicate competing consumer coordination. If the outbox publish fails, the poller retries; if it succeeds but the message is duplicated (e.g., redelivery before ack), the idempotent consumer catches the duplicate at the DB level.

**REQ-DB-011:** An outbox table SHALL be used to guarantee at-least-once delivery to SNS FIFO:

| Column | Type | Description |
|--------|------|-------------|
| `id` | `BIGSERIAL` | Primary key |
| `aggregate_id` | `VARCHAR(255)` | Message correlation ID |
| `event_type` | `VARCHAR(100)` | Event classification |
| `payload` | `JSONB` | SNS message payload |
| `destination_name` | `VARCHAR(512)` | Solace destination this message originated from |
| `target_sns_arn` | `VARCHAR(512)` | Target SNS FIFO topic ARN |
| `message_group_id` | `VARCHAR(128)` | SNS FIFO MessageGroupId for ordering |
| `deduplication_id` | `VARCHAR(128)` | SNS FIFO MessageDeduplicationId |
| `status` | `VARCHAR(20)` | `PENDING`, `PUBLISHED`, `FAILED` |
| `created_at` | `TIMESTAMP WITH TIME ZONE` | Creation timestamp |
| `published_at` | `TIMESTAMP WITH TIME ZONE` | When published to SNS |

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DB-012 | Outbox processing SHALL be triggered via **PostgreSQL `LISTEN/NOTIFY`** for near-real-time delivery. A fallback polling mechanism SHALL run every **500ms** to catch any missed notifications. The `NOTIFY` SHALL be issued by a database trigger on outbox INSERT | Must |
| REQ-DB-013 | Database connection pooling SHALL use **HikariCP** with configurable pool size (default: max 20, min 5) | Must |
| REQ-DB-014 | Connection pool health SHALL be monitored via Spring Boot Actuator and exported to CloudWatch via ADOT Collector | Must |
| REQ-DB-015 | Outbox poller SHALL use `SELECT ... FOR UPDATE SKIP LOCKED` to support concurrent poller instances across all pods without contention | Must |

### 6.4 Data Retention and Archival

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DB-016 | Audit records older than **90 days** SHALL be archived to Amazon S3 (Parquet format) via AWS DMS or custom ETL job | Must |
| REQ-DB-017 | Archived records SHALL be queryable via **Amazon Athena** with a Glue catalog | Should |
| REQ-DB-018 | Audit records older than **365 days** SHALL be purged from RDS | Must |
| REQ-DB-019 | Automated backups SHALL be enabled with **35-day retention** period | Must |
| REQ-DB-020 | **Point-in-time recovery** SHALL be enabled | Must |
| REQ-DB-021 | Archival jobs SHALL run during off-peak hours and SHALL NOT impact production message processing | Must |

### 6.5 Connection Pool Capacity Planning

**REQ-DB-022:** The following connection pool math SHALL be validated during load testing and documented:

| Parameter | Formula / Value |
|-----------|----------------|
| Threads per pod | 16 (REQ-PERF-006) |
| Pool size per pod | threads + 2 = **18** (REQ-PERF-011) |
| HikariCP max per pod | **20** (REQ-DB-013, provides headroom) |
| Max pods per destination | 10 (REQ-CMP-027) |
| Number of destinations | N (configurable) |
| Max total connections | 20 x 10 x N = **200N** |
| RDS `db.r6g.large` max connections | ~1,600 (PostgreSQL default) |
| Constraint | 200N must be < RDS max connections |
| RDS Proxy (if used) | `MaxConnectionsPercent` >= (200N / RDS max connections) x 100 |

> **Example:** With 3 destinations, max connections = 600, well within `db.r6g.large` limits. With 8+ destinations, consider upgrading to `db.r6g.xlarge` or using RDS Proxy for connection multiplexing.

---

## 7. SNS/SQS Fan-out Pattern Requirements

### 7.1 SNS FIFO Configuration

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MSG-001 | An **SNS FIFO topic** SHALL be created for each logical message fan-out group (e.g., `arn:aws:sns:region:account:hermes-orders.fifo`). Multiple Solace destinations MAY share an SNS FIFO topic if they serve the same downstream consumers, or use separate topics for isolation | Must |
| REQ-MSG-002 | SNS FIFO topics SHALL use **server-side encryption** with KMS CMK | Must |
| REQ-MSG-003 | SNS FIFO topics SHALL be configured with **content-based deduplication disabled**; the application SHALL provide explicit `MessageDeduplicationId` (using the Solace message ID or outbox record ID) for precise dedup control | Must |

**REQ-MSG-004:** SNS FIFO message attributes SHALL include:

| Attribute | Type | Purpose |
|-----------|------|---------|
| `messageType` | String | Message classification for subscription filtering |
| `sourceSystem` | String | Origin system identifier (e.g., `solace-hermes`) |
| `sourceDestination` | String | Solace destination name this message originated from |
| `correlationId` | String | End-to-end tracing identifier |
| `priority` | String | Message priority (`HIGH`, `MEDIUM`, `LOW`) |
| `timestamp` | String | ISO 8601 origination timestamp |

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MSG-005 | SNS FIFO access policy SHALL restrict publish permissions to the application's IRSA IAM roles only | Must |
| REQ-MSG-006 | SNS delivery status logging SHALL be enabled for SQS endpoints | Must |

### 7.2 SQS FIFO Configuration

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MSG-007 | Separate **SQS FIFO queues** SHALL be created for each downstream consumer (e.g., `hermes-consumer-a.fifo`, `hermes-consumer-b.fifo`) | Must |
| REQ-MSG-008 | Each SQS FIFO queue SHALL have a corresponding **Dead Letter Queue (DLQ)** (also FIFO) with `maxReceiveCount` of 3 | Must |
| REQ-MSG-009 | SQS FIFO queues SHALL use **server-side encryption** (SSE-KMS with CMK) | Must |
| REQ-MSG-010 | SQS visibility timeout SHALL be set to **6x the expected processing time** of downstream consumers | Must |
| REQ-MSG-011 | SQS message retention period SHALL be **14 days** (maximum) | Must |
| REQ-MSG-012 | SQS **long polling** SHALL be enabled (`WaitTimeSeconds = 20`) for efficient message retrieval | Must |
| REQ-MSG-013 | SNS FIFO subscription **filter policies** SHOULD be used to route specific message types to specific SQS FIFO queues | Should |
| REQ-MSG-018 | SQS FIFO **high-throughput mode** SHALL be enabled to support up to 3,000 messages/s per message group ID (with batching) | Must |

### 7.3 Fan-out Pattern

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MSG-014 | SNS FIFO-to-SQS FIFO subscription SHALL use **raw message delivery** for reduced overhead | Must |
| REQ-MSG-015 | Application SHALL publish to SNS FIFO with explicit `MessageDeduplicationId` (Solace message ID or outbox record ID) and `MessageGroupId` (derived from destination name, correlation ID, or configurable key) for each message | Must |
| REQ-MSG-016 | SQS FIFO queue policies SHALL allow the SNS FIFO topic to send messages (`sqs:SendMessage`) | Must |

### 7.4 FIFO Throughput and Message Group Strategy

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MSG-019 | `MessageGroupId` strategy SHALL be documented per destination. Use the **Solace destination name** as the default group ID. If higher parallelism is needed, use a hash of the `correlationId` modulo a configurable partition count to spread messages across multiple message groups | Must |
| REQ-MSG-020 | SNS FIFO publish operations SHALL use **batching** (up to 10 messages per `PublishBatch` call) to maximize throughput within FIFO rate limits | Must |
| REQ-MSG-021 | Throughput SHALL be validated per message group. If a single message group exceeds 300 msgs/s (FIFO per-group limit), the `MessageGroupId` strategy SHALL be adjusted to distribute load across more groups | Must |

**REQ-MSG-022:** CloudWatch Alarms SHALL monitor:

| Metric | Threshold | Action |
|--------|-----------|--------|
| `NumberOfMessagesPublished` (SNS FIFO) | Drop > 50% over 5 min | Alert operations team |
| `ApproximateNumberOfMessagesVisible` (SQS FIFO) | > 10,000 | Auto-scale consumers + Alert |
| `ApproximateAgeOfOldestMessage` (SQS FIFO) | > 1 hour | Alert operations team |
| `NumberOfMessagesMovedToDlq` (DLQ FIFO) | > 0 | Alert immediately (Critical) |

---

## 8. Disaster Recovery and Business Continuity

### 8.1 Recovery Objectives

| Req ID | Requirement | Target |
|--------|-------------|--------|
| REQ-DR-001 | **Recovery Time Objective (RTO)** | 1 hour for full service restoration |
| REQ-DR-002 | **Recovery Point Objective (RPO)** | 5 minutes maximum data loss |
| REQ-DR-003 | **Availability target** | **99.9%** uptime (~8.76 hours downtime/year). This target applies to single-region operations; regional outage events are excluded from the SLA calculation per standard AWS shared responsibility model |

### 8.2 Multi-AZ Resilience

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DR-004 | ROSA worker nodes SHALL span minimum **2 Availability Zones**. Pod anti-affinity and topology spread constraints SHALL ensure pods are distributed across AZs | Must |
| REQ-DR-005 | RDS Multi-AZ SHALL provide automatic failover (typically < 60 seconds) | Must |
| REQ-DR-006 | NAT Gateways SHALL be deployed **in each AZ** used by the ROSA cluster for AZ-independent connectivity. All NAT Gateway Elastic IPs SHALL be pre-registered with the Solace operations team for IP whitelisting. A documented **EIP coordination procedure** SHALL exist for AZ additions or NAT Gateway replacements | Must |
| REQ-DR-007 | SNS FIFO and SQS FIFO are inherently multi-AZ; no additional configuration required | N/A |
| REQ-DR-017 | ROSA cluster **etcd** is managed by Red Hat/AWS and is automatically backed up and replicated across AZs | N/A |

### 8.3 Cross-Region DR (If Required)

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DR-008 | For cross-region DR, RDS **cross-region read replicas** SHALL be provisioned in the DR region | Should |
| REQ-DR-009 | SNS FIFO topics and SQS FIFO queues SHALL be replicated in the DR region via infrastructure-as-code (Terraform + Helm) | Should |
| REQ-DR-010 | Container images SHALL be replicated to **ECR in the DR region** | Should |
| REQ-DR-011 | A standby **ROSA cluster** in the DR region SHALL be provisioned via Terraform, with application Helm charts deployable on failover | Should |
| REQ-DR-018 | Route 53 health checks with **DNS failover** SHALL route traffic to the DR region upon primary failure (applicable if an external API is added in the future) | Should |

### 8.4 Backup Strategy

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-DR-012 | RDS automated backups: daily snapshots with **35-day retention** | Must |
| REQ-DR-013 | RDS manual snapshots before major changes, **copied to DR region** | Must |
| REQ-DR-014 | Application configuration backed up in version control (Helm values files, ConfigMaps, ExternalSecret manifests) | Must |
| REQ-DR-015 | Infrastructure defined as code (Terraform for AWS, Helm for OpenShift) stored in **version control** (Git) | Must |
| REQ-DR-016 | DR runbook SHALL be documented and **tested quarterly** | Must |

### 8.5 Failure Scenarios and Mitigation

| Failure Scenario | Detection | Mitigation | Recovery |
|-----------------|-----------|-------------|----------|
| Solace connection lost | SessionEventHandler + CloudWatch alarm | Automatic fixed-interval reconnection (`reconnectRetries: -1`, 3s interval) | Auto-reconnect; messages buffered on Solace broker side |
| RDS primary failure | RDS event notification + CloudWatch alarm | Multi-AZ automatic failover; application applies **backpressure to Solace** (pauses consumption) during failover | Automatic; < 60s downtime; consumption resumes after reconnection |
| Pod crash | Kubernetes liveness probe failure | Deployment controller replaces pod automatically | New pod launched within seconds; orphaned outbox records picked up by other pods via SKIP LOCKED |
| Worker node failure | Kubernetes node health check | Pods rescheduled to healthy nodes by scheduler; Cluster Autoscaler adds replacement node | Automatic; PDB ensures minimum availability during rescheduling |
| SNS FIFO publish failure | CloudWatch delivery metrics | Outbox pattern retries pending messages | Outbox poller retries every 500ms |
| AZ outage | AWS health events | Pods redistributed to healthy AZs by scheduler; Cluster Autoscaler scales healthy AZ nodes | Automatic via Kubernetes scheduler + pod anti-affinity |
| Region outage | Route 53 health check failure | DR region ROSA cluster activation (if configured) | Manual or automatic (15-min DNS TTL) |
| Certificate expiry | CloudWatch alarm (30/14/7 day) | Automated rotation via Secrets Manager; ESO syncs new secret to K8s; rolling restart of pods | Pre-rotation prevents outage |
| Database connection pool exhaustion | Actuator health + CloudWatch metric | Circuit breaker trips; **backpressure applied to Solace consumer** (pauses message receipt) | Pool recovers when load decreases; consumption resumes |
| ROSA cluster upgrade | Planned maintenance window | Rolling worker node upgrades; PDB ensures availability | Automatic; zero-downtime with proper PDB and pod disruption budgets |

---

## 9. Performance and Throughput Requirements

### 9.1 Throughput Targets

| Req ID | Requirement | Target |
|--------|-------------|--------|
| REQ-PERF-001 | System SHALL sustain normal load per destination | **1,000 msgs/s** |
| REQ-PERF-002 | System SHALL handle burst capacity per destination for up to 5 minutes | **3,000 msgs/s** (SNS FIFO limit with batching and high-throughput mode). Requires multiple `MessageGroupId` values for parallelism |
| REQ-PERF-003 | End-to-end latency (Solace receive to SNS FIFO publish) at P95 under normal load | **< 500ms** |
| REQ-PERF-004 | End-to-end latency (Solace receive to SQS FIFO delivery) at P99 under burst load | **< 2 seconds** |

> **Note on latency measurement:** P95 latency is measured from Solace message receipt to SNS FIFO publish completion (not SQS delivery, which adds SNS-to-SQS propagation time). The PostgreSQL `LISTEN/NOTIFY` outbox trigger ensures sub-100ms latency between DB commit and outbox poller pickup, making the 500ms P95 achievable.

### 9.2 Solace Consumer Performance

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-PERF-005 | Solace consumer prefetch count SHALL be tunable per destination (default: **32 messages**). Prefetch of 256 is inappropriate for transactional DB processing (5ms+ per message) — on pod crash, up to 255 unprocessed messages in the JCSMP buffer would be redelivered, wasting processing time, causing a processing spike, and potentially exhausting the Solace queue's `max-redelivery-count` for messages that were never actually processed. Prefetch of 32 provides pipeline efficiency while limiting the data-at-risk window. `SUB_ACK_WINDOW_SIZE` SHALL be aligned with prefetch (32) | Must |
| REQ-PERF-006 | Application SHALL support concurrent message processing via configurable thread pool per destination (default: **16 threads**) | Must |
| REQ-PERF-007 | Solace flow window size SHALL be tuned based on message size and network latency | Must |
| REQ-PERF-008 | Application SHALL use asynchronous message receipt handlers (not polling) | Must |

### 9.3 Database Performance

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-PERF-009 | Audit table INSERT latency SHALL be **< 5ms at P95** | Must |
| REQ-PERF-010 | Appropriate indexes SHALL be created on `message_id`, `correlation_id`, `status`, `created_at`, and `source_destination` columns | Must |
| REQ-PERF-011 | Database connection pool size per pod SHALL be tuned to match concurrent processing threads (`pool size = threads + 2`). See Section 6.5 for total connection capacity planning | Must |
| REQ-PERF-012 | Batch inserts SHOULD be used when processing multiple messages (batch size: **100**) | Should |

### 9.4 SNS FIFO Performance

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-PERF-013 | SNS FIFO publish operations SHALL use the **AWS SDK async client** for non-blocking I/O | Must |
| REQ-PERF-014 | SNS FIFO publish batching SHALL be used (`PublishBatch` API, up to **10 messages per batch**) to maximize throughput within FIFO rate limits | Must |

---

## 10. Load Testing Requirements

### 10.1 Test Strategy

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-LT-001 | Load testing SHALL be performed using a dedicated **performance testing environment** (separate ROSA namespace or cluster) that mirrors production topology | Must |
| REQ-LT-002 | Load testing tools: **Solace SDKPerf** for Solace message generation; **Apache JMeter**, **Gatling**, or **Locust** for HTTP endpoints | Must |
| REQ-LT-003 | **Abbreviated performance regression tests** (5-10 minutes, smoke-level) SHALL be integrated into the CI/CD pipeline as a **gate for production deployment**. Full load test suite SHALL run on a **weekly schedule** and before major releases | Must |

### 10.2 Test Scenarios

| Scenario | Description | Duration | Target |
|----------|-------------|----------|--------|
| **Baseline** | Normal steady-state load | 1 hour | 1,000 msgs/s sustained per destination |
| **Burst** | Sudden traffic spike | 15 minutes | 3,000 msgs/s per destination |
| **Endurance / Soak** | Sustained load over extended time | 8 hours | 800 msgs/s (80% capacity) per destination |
| **Stress** | Beyond capacity limits | 30 minutes | Increase until failure; identify breaking point |
| **Recovery** | Restart after controlled failure | 30 minutes | Verify zero message loss; all audited |
| **Reconnection** | Solace connection drop during load | 1 hour | Verify automatic reconnection and message continuity |
| **DB Failover** | RDS failover during message processing | 30 minutes | Verify transaction integrity and backpressure behavior post-failover |
| **Scaling** | Auto-scale under increasing load | 1 hour | Verify HPA/KEDA scales pods and Cluster Autoscaler adds nodes correctly |
| **Multi-Destination** | All destinations under concurrent load | 1 hour | Verify isolation between consumer groups; no cross-destination interference |
| **Solace Connection Capacity** | Max pods across all destinations | 30 minutes | Verify Solace broker handles max concurrent connections |
| **FIFO Throughput** | Validate SNS/SQS FIFO rate limits | 30 minutes | Verify MessageGroupId strategy achieves target throughput |
| **Node Failure** | Kill a worker node during load | 30 minutes | Verify pods reschedule and message processing continues without loss |

### 10.3 Success Criteria

| Req ID | Criterion | Threshold |
|--------|-----------|-----------|
| REQ-LT-004 | Message loss under all test scenarios | **Zero** (verified via audit table count vs. Solace publish count) |
| REQ-LT-005 | P95 latency under baseline load (Solace receive to SNS publish) | **< 500ms** |
| REQ-LT-006 | P99 latency under burst load (Solace receive to SQS delivery) | **< 2 seconds** |
| REQ-LT-007 | CPU utilization under baseline load | **< 70%** |
| REQ-LT-008 | Memory utilization under all scenarios | **< 80%** |
| REQ-LT-009 | Database connection pool utilization under baseline | **< 80%** |
| REQ-LT-010 | OutOfMemoryError or thread pool exhaustion | **Zero** under any scenario |
| REQ-LT-011 | HPA/KEDA scaling response time | Triggers within **3 minutes** of threshold breach |

---

## 11. Monitoring and Observability

### 11.1 Observability Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Metrics Collection | AWS Distro for OpenTelemetry (ADOT) Collector (DaemonSet on ROSA) | Collects application metrics (Prometheus format) and ships to CloudWatch |
| Log Collection | ADOT Collector or Fluent Bit (DaemonSet) | Collects stdout/stderr from pods and ships to CloudWatch Logs |
| Distributed Tracing | ADOT Collector with X-Ray exporter | Collects OpenTelemetry traces and exports to AWS X-Ray |
| Metrics Storage | Amazon CloudWatch Metrics | Centralized metrics (custom + AWS service metrics) |
| Log Storage | Amazon CloudWatch Logs | Centralized log aggregation |
| Trace Storage | AWS X-Ray | Distributed trace analysis |
| Dashboards & Alarms | Amazon CloudWatch Dashboards + Alarms | Visualization and alerting |

**REQ-MON-012:** The **ADOT Collector** SHALL be deployed as a DaemonSet on the ROSA cluster, configured to:
- Scrape Prometheus metrics from application pods (Spring Boot Actuator `/actuator/prometheus` endpoint)
- Collect container logs from stdout/stderr
- Receive OpenTelemetry traces from the application
- Export metrics to CloudWatch, logs to CloudWatch Logs, and traces to X-Ray

**REQ-MON-013:** The ADOT Collector pods SHALL use IRSA to assume an IAM role with permissions for CloudWatch, CloudWatch Logs, and X-Ray write operations.

### 11.2 Metrics (CloudWatch)

**REQ-MON-001:** Custom CloudWatch metrics SHALL be published for each destination (using `Destination` dimension):

| Metric Name | Namespace | Description | Unit |
|-------------|-----------|-------------|------|
| `solace.messages.received` | `CAGHermes` | Messages received from Solace per minute | Count |
| `solace.messages.processed` | `CAGHermes` | Messages successfully processed per minute | Count |
| `solace.messages.failed` | `CAGHermes` | Messages failed processing per minute | Count |
| `solace.connection.status` | `CAGHermes` | Connection status (1=connected, 0=disconnected) | None |
| `solace.reconnect.count` | `CAGHermes` | Reconnection attempts | Count |
| `solace.dmq.depth` | `CAGHermes` | Solace DMQ message count (per destination, via SEMP) | Count |
| `audit.insert.latency` | `CAGHermes` | RDS audit insert time | Milliseconds |
| `sns.publish.latency` | `CAGHermes` | SNS FIFO publish time | Milliseconds |
| `outbox.pending.count` | `CAGHermes` | Number of pending outbox records | Count |
| `outbox.notify.latency` | `CAGHermes` | Time from outbox INSERT to poller pickup (LISTEN/NOTIFY) | Milliseconds |
| `processing.e2e.latency` | `CAGHermes` | End-to-end processing time (Solace receive to SNS publish) | Milliseconds |

### 11.3 Logging

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MON-002 | Application SHALL use **structured JSON logging** (Logback with JSON encoder or Log4j2 JSON layout) to stdout | Must |
| REQ-MON-003 | Log levels: `ERROR` for failures, `WARN` for retries/degradation, `INFO` for lifecycle events, `DEBUG` for message-level tracing | Must |
| REQ-MON-004 | Each log entry SHALL include: `timestamp`, `level`, `correlationId`, `messageId`, `destination`, `podName`, `threadName`, `logger`, `message`, `traceId` | Must |
| REQ-MON-005 | Logs SHALL be shipped to CloudWatch Logs (via ADOT/Fluent Bit DaemonSet) with **log group per destination per environment** and **90-day retention** (aligned with VPC Flow Log and CloudTrail retention) | Must |
| REQ-MON-006 | CloudWatch Logs Insights queries SHALL be pre-built for common troubleshooting patterns (per-destination filtering, error correlation, latency analysis, pod-level filtering) | Should |

### 11.4 Distributed Tracing

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-MON-007 | **AWS X-Ray** SHALL be enabled for end-to-end request tracing via the ADOT Collector and OpenTelemetry SDK in the application | Must |
| REQ-MON-008 | Trace context SHALL propagate from Solace message receipt through RDS and SNS operations | Must |
| REQ-MON-009 | Custom trace spans SHALL be created for Solace operations, RDS transactions, and SNS FIFO publishes using OpenTelemetry instrumentation | Must |

### 11.5 Alerting

**REQ-MON-010:** CloudWatch Alarms SHALL be configured per destination:

| Alarm Name | Condition | Severity | Notification |
|------------|-----------|----------|-------------|
| Solace Disconnected | `connection.status = 0` for > 1 min | **Critical** | SNS -> PagerDuty/OpsGenie |
| High Error Rate | `failed/received > 5%` over 5 min | **High** | SNS -> Slack + PagerDuty |
| High E2E Latency | `P95 > 1s` over 5 min | **Medium** | SNS -> Slack |
| DLQ Messages (SQS) | DLQ FIFO visible count > 0 | **High** | SNS -> Slack + PagerDuty |
| DMQ Messages (Solace) | `solace.dmq.depth > 0` | **Critical** | SNS -> Slack + PagerDuty |
| RDS CPU High | CPU > 80% for 5 min | **Medium** | SNS -> Slack |
| RDS Storage Low | `FreeStorageSpace < 10 GB` | **High** | SNS -> Slack |
| Outbox Backlog | `pending.count > 100` for > 1 min | **High** | SNS -> Slack + PagerDuty |
| Certificate Expiry | Days to expiry < 14 | **Critical** | SNS -> Email + Slack |
| Pod Restarts | Pod restart count > 3 in 10 min | **High** | SNS -> Slack + PagerDuty |

### 11.6 Dashboards

**REQ-MON-011:** A CloudWatch Dashboard SHALL be created with per-destination views:

- Real-time message throughput (received, processed, failed) per destination
- End-to-end latency percentiles (P50, P95, P99) per destination
- Solace connection status indicator per destination
- RDS metrics (CPU, active connections, IOPS, read/write latency)
- SNS FIFO / SQS FIFO metrics (published, delivered, DLQ depth, age of oldest message) per topic
- Pod metrics (CPU, memory, running pod count, restarts) per Deployment
- ROSA cluster metrics (node count, pending pods, node CPU/memory utilization)
- Outbox pending count trend line per destination
- Aggregate cross-destination summary view

---

## 12. Middleware Patterns and Best Practices

### 12.1 Message Processing Patterns

| Req ID | Pattern | Description |
|--------|---------|-------------|
| REQ-PAT-001 | **Idempotent Consumer** | Every message processor SHALL be idempotent, using the Solace message ID stored in the audit table to detect and skip duplicates. This is required as a defense-in-depth measure even with FIFO deduplication, since dedup windows are finite (5 minutes) |
| REQ-PAT-002 | **Transactional Outbox** | Database writes and messaging SHALL be coordinated via the outbox pattern to prevent dual-write inconsistencies. The outbox is triggered via PostgreSQL `LISTEN/NOTIFY` with fallback polling |
| REQ-PAT-003 | **Competing Consumers** | Multiple pods within the same Deployment SHALL consume from the same Solace queue using non-exclusive queue access for horizontal scaling. Each pod runs its own outbox poller using `SELECT ... FOR UPDATE SKIP LOCKED` to avoid contention |
| REQ-PAT-004 | **Dead Letter Channel** | Messages that fail processing after max retries SHALL be routed to a DLQ (both Solace-side DMQ and SQS FIFO-side DLQ) with alerting |

**REQ-PAT-005: Circuit Breaker** - Application SHALL implement circuit breaker pattern (via Resilience4j) for RDS and SNS FIFO calls:

| State | Condition | Behavior |
|-------|-----------|----------|
| **Closed** | Normal operation | Requests pass through |
| **Open** | Failure rate > 50% in 10-call sliding window | Requests fail fast for 30 seconds; **Solace consumption is paused** (backpressure) |
| **Half-Open** | After 30s timeout | Allow 5 probe requests; if 3 succeed, close circuit and resume Solace consumption |

### 12.2 Reliability Patterns

| Req ID | Pattern | Description |
|--------|---------|-------------|
| REQ-PAT-006 | **Retry with Backoff** | All external calls (RDS, SNS FIFO) SHALL retry with exponential backoff (initial 100ms, max 10s, factor 2x, jitter +/-20%). Note: Solace reconnection uses JCSMP's built-in fixed-interval retry (`reconnectRetries: -1`, 3s interval) — not application-level exponential backoff |
| REQ-PAT-007 | **Bulkhead** | Separate thread pools SHALL isolate Solace consumption, RDS writes, and SNS FIFO publishes to prevent resource starvation across concerns |
| REQ-PAT-008 | **Backpressure to Solace** | If RDS or SNS is unavailable (circuit breaker open), the application SHALL **pause Solace message consumption** (stop the Solace flow/consumer). Messages remain safely queued on the Solace broker. Consumption resumes when the circuit breaker transitions to closed. **No in-memory message buffering is permitted**, as it violates the zero-message-loss guarantee if the pod crashes |
| REQ-PAT-009 | **Message Ordering** | If strict ordering is required for a destination, the application SHALL use Solace exclusive queues and single-consumer mode (single-replica Deployment). On the SNS/SQS FIFO side, ordering is maintained within a `MessageGroupId` |

### 12.3 Data Consistency Patterns

| Req ID | Pattern | Description |
|--------|---------|-------------|
| REQ-PAT-010 | **Effectively Exactly-Once Processing** | Combine idempotent consumer + transactional outbox + client acknowledgment at DB commit + SNS/SQS FIFO deduplication for effectively exactly-once semantics end-to-end. Note: downstream consumers MUST also implement idempotency as a defense-in-depth measure |
| REQ-PAT-011 | **Claim-Check (Conditional)** | For messages exceeding 200 KB, store the payload in S3 and pass only a reference through SNS/SQS FIFO. See REQ-SOL-025/026 |

---

## 13. AWS Well-Architected Framework Alignment

### 13.1 Operational Excellence

| Principle | Implementation |
|-----------|---------------|
| Infrastructure as Code | AWS infrastructure in Terraform; OpenShift resources in Helm charts; all version controlled in Git |
| CI/CD | Automated pipeline: build -> test -> security scan -> container build -> deploy to ROSA -> smoke test -> abbreviated perf test |
| Runbooks | Documented procedures for: Solace disconnect, DB failover, certificate rotation, destination onboarding, ROSA cluster upgrade, node scaling |
| Game Days | Quarterly chaos engineering exercises (Solace disconnect, AZ failure, RDS failover, worker node termination) |
| Observability | CloudWatch metrics (per destination via ADOT), structured logs, X-Ray traces, dashboards, and alarms |

### 13.2 Security

| Principle | Implementation |
|-----------|---------------|
| Identity & Access | IRSA (IAM Roles for Service Accounts via STS) with least-privilege policies; no long-term credentials; Secrets Manager + ESO for all secrets; IAM database authentication for RDS |
| Detection | GuardDuty, Security Hub, CloudTrail, VPC Flow Logs, Config Rules |
| Infrastructure Protection | Private subnets, ROSA private API server, Security Groups on nodes, **NetworkPolicies** for pod-level isolation, NACLs, NAT Gateway, **VPC Endpoints for all AWS services**, **OpenShift SCCs** for pod security |
| Data Protection | Encryption at rest (KMS CMK) and in transit (TLS 1.2); log redaction for PII; data classification per destination |
| Incident Response | Automated alerting via CloudWatch -> SNS -> PagerDuty; security event correlation via Security Hub |

### 13.3 Reliability

| Principle | Implementation |
|-----------|---------------|
| Fault Isolation | Multi-AZ ROSA cluster; per-destination Deployments; pod anti-affinity and topology spread; PDBs; bulkhead pattern; circuit breakers; separate thread pools; **backpressure to Solace** (no in-memory buffering) |
| Change Management | Rolling deployments via OpenShift; Helm rollback on failure; canary deployments via progressive delivery |
| Failure Management | Auto-healing (Kubernetes pod restart); HPA/KEDA auto-scaling per destination; Cluster Autoscaler for nodes; Solace auto-reconnect; DR plan |
| Testing | Chaos engineering; failover testing; load testing; integration testing with Testcontainers |

### 13.4 Performance Efficiency

| Principle | Implementation |
|-----------|---------------|
| Selection | ROSA on right-sized EC2 instances (m6i.xlarge), RDS PostgreSQL (`db.r6g.large`), provisioned IOPS (gp3), SNS/SQS FIFO with high-throughput mode |
| Review | Regular performance benchmarking; abbreviated perf tests in CI/CD; full load tests weekly |
| Monitoring | P50/P95/P99 latency tracking per destination; throughput dashboards; capacity planning alerts |
| Trade-offs | Async processing via outbox with LISTEN/NOTIFY; batch operations for DB and SNS FIFO; HikariCP connection pooling |

### 13.5 Cost Optimization

| Principle | Implementation |
|-----------|---------------|
| Expenditure Awareness | AWS Cost Explorer; mandatory resource tagging (including `Destination` tag); Kubernetes labels for cost allocation; billing alarms per environment |
| Right-sizing | HPA/KEDA auto-scaling per destination (pods match demand); Cluster Autoscaler (nodes match pod demand); Reserved Instances or Savings Plans for RDS and ROSA worker nodes |
| Resource Management | Data lifecycle policies (90-day RDS, 365-day S3 archive); log retention aligned at 90 days; ResourceQuotas to prevent over-provisioning |
| Network Optimization | **VPC Endpoints** eliminate NAT Gateway data processing charges for AWS API traffic; only Solace traffic traverses NAT Gateway |
| Optimization | Spot Instances for non-production ROSA worker nodes (via mixed machine pools); S3 Intelligent-Tiering for archives |

### 13.6 Sustainability

| Principle | Implementation |
|-----------|---------------|
| Resource Efficiency | HPA/KEDA scales pods to match demand; Cluster Autoscaler removes idle nodes; right-sized containers via resource requests/limits |
| Data Management | Lifecycle policies; archive to S3 Glacier for cold data beyond 365 days |
| Process Optimization | Efficient serialization (compact JSON); batch processing via SNS FIFO PublishBatch; PostgreSQL LISTEN/NOTIFY vs polling |

---

## 14. Infrastructure as Code Requirements

| Req ID | Requirement | Priority |
|--------|-------------|----------|
| REQ-IAC-001 | All **AWS infrastructure** SHALL be defined using **Terraform**: VPC, subnets, NAT Gateways, VPC Endpoints, RDS, SNS FIFO, SQS FIFO, IAM roles/policies, KMS keys, Secrets Manager secrets, CloudWatch alarms/dashboards, and the ROSA cluster itself (via `rhcs` Terraform provider or ROSA CLI) | Must |
| REQ-IAC-002 | Terraform state SHALL be stored in **S3 with DynamoDB locking** and encryption enabled | Must |
| REQ-IAC-003 | Terraform infrastructure SHALL be organized into modules: `networking` (VPC, subnets, NAT, VPC endpoints), `rosa` (ROSA cluster, machine pools), `database` (RDS, Proxy), `messaging` (SNS FIFO, SQS FIFO), `security` (IAM, KMS, Secrets Manager), `monitoring` (CloudWatch alarms, dashboards) | Must |
| REQ-IAC-004 | **Environment parity** SHALL be maintained via parameterized modules (`dev`, `staging`, `production`) | Must |
| REQ-IAC-005 | All infrastructure changes SHALL go through **code review and CI/CD pipeline** with `terraform plan` review before `apply` | Must |
| REQ-IAC-006 | New Solace destinations SHALL be onboardable via Terraform variables (destination name, Solace config, SNS topic, scaling parameters) and Helm values without modifying module or chart source code | Must |
| REQ-IAC-007 | All **OpenShift application resources** SHALL be defined using **Helm charts**: Deployments, Services, ConfigMaps, ExternalSecrets, HPAs, KEDA ScaledObjects, NetworkPolicies, PDBs, ServiceAccounts, and RBAC. Helm charts SHALL be version-controlled in Git | Must |
| REQ-IAC-008 | Helm values files SHALL be organized per environment (`values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`) with per-destination overrides | Must |
| REQ-IAC-009 | **OpenShift Operators** SHALL be used for: External Secrets Operator (ESO), KEDA, and ADOT Collector. Operators SHALL be installed via OperatorHub/OLM (Operator Lifecycle Manager) | Must |

---

## 15. CI/CD Pipeline Requirements

**REQ-CICD-001:** Pipeline stages:

| Stage | Tools | Quality Gate |
|-------|-------|-------------|
| **Source** | GitHub / GitLab / Bitbucket | Branch protection; PR approval required |
| **Build** | Maven / Gradle | Compilation success |
| **Unit Test** | JUnit 5, Mockito | > 80% code coverage |
| **Static Analysis** | SonarQube, SpotBugs | No critical/blocker issues |
| **Security Scan** | Snyk, Trivy, OWASP Dependency Check | No high/critical CVEs |
| **Container Build** | Docker / Buildah / OpenShift Builds | Image scan pass (ECR scan + Red Hat Quay/ACS scan) |
| **Push to ECR** | AWS CLI / Skopeo | Image pushed and tagged |
| **Integration Test** | Testcontainers (Solace, PostgreSQL) | All integration tests pass |
| **Perf Smoke Test** | JMeter / Gatling / SDKPerf | Abbreviated 5-10 min regression test passes latency/throughput thresholds |
| **Deploy Staging** | Helm upgrade to ROSA staging namespace | Smoke tests pass; Kubernetes readiness probes healthy |
| **Deploy Production** | Helm upgrade to ROSA production namespace | Rolling update with health checks; automatic rollback on probe failure |

**REQ-CICD-002:** Helm-based deployments SHALL support:
- Rolling updates with `maxUnavailable: 0` and `maxSurge: 1` for zero-downtime deployments
- Automatic rollback via `helm rollback` if readiness probes fail within a configurable window
- Per-destination deployments (deploy a single destination without affecting others)

---

## 16. Non-Functional Requirements Summary

| Category | Requirement | Target |
|----------|-------------|--------|
| Availability | Uptime SLA | **99.9%** (single-region, regional outages excluded) |
| Throughput | Sustained message rate (per destination) | **1,000 msgs/s** |
| Throughput | Burst message rate (per destination, 5 min) | **3,000 msgs/s** (SNS FIFO with batching + high-throughput mode) |
| Latency | End-to-end P95 (Solace receive to SNS publish, normal load) | **< 500 ms** |
| Latency | End-to-end P99 (Solace receive to SQS delivery, burst load) | **< 2 seconds** |
| Recovery | Recovery Time Objective (RTO) | **1 hour** |
| Recovery | Recovery Point Objective (RPO) | **5 minutes** |
| Scalability | Pod scaling range (per destination) | **2-10 pods** (via HPA/KEDA) |
| Scalability | Cluster node scaling | **3-12 worker nodes** (via Cluster Autoscaler) |
| Scalability | Multiple destinations | **N destinations, independently scalable** |
| Data Retention | Online data (RDS PostgreSQL) | **90 days** |
| Data Retention | Archived data (S3) | **365 days** |
| Log Retention | All logs (app, VPC Flow, CloudTrail) | **90 days** (aligned) |
| Security | Encryption in transit | **TLS 1.2+** |
| Security | Encryption at rest | **AES-256 (KMS CMK)** |
| Security | Network isolation | **VPC Endpoints for AWS services; NetworkPolicies for pod isolation; NAT for Solace only** |
| Security | Container security | **Restricted SCC; non-root; Pod Security Standards** |
| Compliance | Audit trail | **Full message lifecycle per destination** |
| Compliance | Secret rotation | **90-day cycle** (Secrets Manager + ESO sync) |
| Compliance | Data classification | **Documented per destination** |
| Message Delivery | Semantics | **Effectively exactly-once** (FIFO dedup + idempotent consumers) |
| Message Size | Maximum payload | **200 KB** (claim-check for larger) |
| Platform | Container orchestration | **Red Hat OpenShift on AWS (ROSA) 4.14+** |

---

## 17. Glossary

| Term | Definition |
|------|-----------|
| **ROSA** | Red Hat OpenShift Service on AWS — a managed OpenShift service jointly operated by Red Hat and AWS |
| **OpenShift** | Red Hat's enterprise Kubernetes platform with additional security, developer, and operational features |
| **OCP** | OpenShift Container Platform — the on-premise/self-managed version of OpenShift (ROSA is the AWS-managed equivalent) |
| **STS** | AWS Security Token Service — used by ROSA for short-lived IAM credentials via IRSA |
| **IRSA** | IAM Roles for Service Accounts — mechanism allowing Kubernetes pods to assume IAM roles via annotated ServiceAccounts and STS |
| **ESO** | External Secrets Operator — Kubernetes operator that syncs secrets from external providers (AWS Secrets Manager, SSM) into Kubernetes Secrets |
| **KEDA** | Kubernetes Event-Driven Autoscaler — extends HPA with custom metric sources (CloudWatch, Prometheus, etc.) |
| **HPA** | Horizontal Pod Autoscaler — Kubernetes native pod scaling based on CPU, memory, or custom metrics |
| **SCC** | Security Context Constraint — OpenShift-specific policy controlling pod security privileges (equivalent to Pod Security Standards) |
| **OLM** | Operator Lifecycle Manager — OpenShift component for installing and managing Operators |
| **ADOT** | AWS Distro for OpenTelemetry — AWS-supported distribution of the OpenTelemetry project for metrics, logs, and traces collection |
| **PDB** | Pod Disruption Budget — Kubernetes object limiting voluntary disruptions to maintain availability |
| **NetworkPolicy** | Kubernetes resource for controlling pod-to-pod and pod-to-external network traffic |
| **Helm** | Kubernetes package manager for templating and deploying application manifests |
| **Solace PubSub+** | Enterprise messaging middleware supporting publish-subscribe, queueing, request-reply, and streaming patterns |
| **JCSMP** | Java Client for Solace Message Patterns — Solace's native high-performance Java API. Maven: `com.solace:sol-jcsmp:10.21+` |
| **JMS** | Java Message Service — standard Java API for message-oriented middleware (not used in this architecture — see REQ-SOL-001) |
| **SEMP** | Solace Element Management Protocol — REST API for broker monitoring and management. SEMPv2 (JSON) is used |
| **INDIVIDUAL_ACKNOWLEDGE** | JCSMP ack mode where each message is individually acknowledged, preventing implicit cumulative ack of unprocessed messages during concurrent processing |
| **FlowReceiver** | JCSMP API for consuming guaranteed messages from a Solace queue with explicit flow lifecycle control (start/stop) |
| **Message VPN** | Virtual Message VPN — a virtual partition in Solace for multi-tenancy and isolation |
| **SMF** | Solace Message Format — Solace's proprietary wire protocol optimized for low latency |
| **DMQ** | Dead Message Queue — Solace's equivalent of a dead-letter queue for undeliverable messages |
| **TLS** | Transport Layer Security — cryptographic protocol for secure communication |
| **mTLS** | Mutual TLS — both client and server authenticate via certificates |
| **SNS FIFO** | Amazon Simple Notification Service (FIFO) — managed pub/sub with message ordering and deduplication |
| **SQS FIFO** | Amazon Simple Queue Service (FIFO) — managed message queue with exactly-once processing and ordering |
| **DLQ** | Dead Letter Queue — queue for messages that cannot be successfully processed |
| **RDS** | Amazon Relational Database Service — managed relational database |
| **KMS** | AWS Key Management Service — managed encryption key service |
| **CMK** | Customer Managed Key — customer-controlled encryption key in KMS |
| **IAM** | AWS Identity and Access Management |
| **IaC** | Infrastructure as Code — managing infrastructure through code (Terraform, Helm) |
| **VPC Endpoint** | AWS PrivateLink-powered endpoint enabling private connectivity to AWS services without traversing the internet |
| **RTO** | Recovery Time Objective — maximum acceptable time to restore service |
| **RPO** | Recovery Point Objective — maximum acceptable data loss measured in time |
| **HikariCP** | High-performance JDBC connection pool for Java |
| **Resilience4j** | Lightweight fault tolerance library for Java (circuit breaker, retry, bulkhead) |
| **Transactional Outbox** | Pattern ensuring atomicity between database writes and message publishing |
| **Claim-Check** | Pattern for handling large messages by storing payload externally and passing a reference |
| **LISTEN/NOTIFY** | PostgreSQL mechanism for real-time event notification between database sessions |
| **Consumer Group** | A set of pods (Deployment replicas) consuming from the same Solace destination |
| **Destination** | A distinct Solace topic subscription or queue binding served by a dedicated consumer group |
| **MessageGroupId** | SNS/SQS FIFO attribute that determines message ordering scope and parallelism |
| **MessageDeduplicationId** | SNS/SQS FIFO attribute used for server-side deduplication within a 5-minute window |
| **UBI** | Red Hat Universal Base Image — a freely redistributable container base image from Red Hat, designed for OpenShift compatibility |

---

## 18. Appendices

### Appendix A: Solace Connection Configuration Example

**`application.yml` (Spring Boot + Solace Spring Boot Starter / JCSMP) — Per-Destination Configuration**

```yaml
solace:
  java:
    host: tcps://broker.example.com:55443    # Use comma-separated for HA: tcps://primary:55443,tcps://standby:55443
    msgVpn: prod-vpn
    clientUsername: ${SOLACE_USERNAME}         # From K8s Secret (via ESO from Secrets Manager)
    clientPassword: ${SOLACE_PASSWORD}         # From K8s Secret (via ESO from Secrets Manager)
    clientName: aws-hermes-${DESTINATION_NAME}-${POD_UID}  # Pod UID prevents name collisions during rolling updates
    connectRetries: 5                          # Initial connection attempts
    reconnectRetries: -1                       # INFINITE reconnect after session loss (CRITICAL)
    reconnectRetryWaitInMillis: 3000           # Fixed 3s interval (JCSMP does not support exponential backoff natively)
    apiProperties:
      # TLS Configuration
      SSL_TRUST_STORE: /app/certs/truststore.jks     # Mounted from K8s Secret volume (via ESO)
      SSL_TRUST_STORE_PASSWORD: ${TRUSTSTORE_PASSWORD}
      SSL_VALIDATE_CERTIFICATE: true
      SSL_VALIDATE_CERTIFICATE_DATE: true
      SSL_PROTOCOL: TLSv1.2
      SSL_EXCLUDED_PROTOCOLS: TLSv1,TLSv1.1         # Explicitly exclude old TLS
      # Transport Tuning (WAN-optimized)
      SUB_ACK_WINDOW_SIZE: 32                        # Aligned with prefetch (32) — controls broker delivery window
      SOCKET_RECEIVE_BUFFER_SIZE: 131072             # 128 KB TCP receive buffer for WAN throughput
      SOCKET_SEND_BUFFER_SIZE: 65536                 # 64 KB TCP send buffer
      # Keepalive (WAN-tolerant)
      KEEP_ALIVE_INTERVAL_IN_MILLIS: 3000            # 3s keepalive interval
      KEEP_ALIVE_LIMIT: 5                            # 5 missed keepalives = 15s tolerance (WAN-appropriate)
      # Message Compression
      MESSAGE_COMPRESSION_LEVEL: 6                   # Level 6 — good compression ratio with moderate CPU overhead
      # Reconnection Behavior
      REAPPLY_SUBSCRIPTIONS: true                    # Re-subscribe to topics after reconnection
      GENERATE_SEQUENCE_NUMBERS: true                # For message ordering verification

# NOTE: Spring Cloud Stream Solace Binder is NOT used.
# The application uses direct JCSMP FlowReceiver via Solace Spring Boot Starter
# for full control over ack timing, flow lifecycle, and backpressure.

hermes:
  destination:
    name: ${SOLACE_DESTINATION:hermes/events}
    queue-name: hermes.${DESTINATION_NAME:events}    # Solace queue name (broker-side provisioned)
    destination-type: ${DESTINATION_TYPE:QUEUE}       # QUEUE or TOPIC
    access-type: NON_EXCLUSIVE                        # For competing consumers
    ack-mode: INDIVIDUAL                              # INDIVIDUAL_ACKNOWLEDGE (not cumulative CLIENT_ACK)
    prefetch: 32                                      # Reduced from 256 — limits data-at-risk window for transactional processing
    concurrency: 16                                   # Concurrent processing threads
    target-sns-arn: ${TARGET_SNS_ARN}
    message-group-strategy: DESTINATION_NAME           # or CORRELATION_HASH
    message-group-partitions: 10                       # for CORRELATION_HASH strategy
    max-payload-size-bytes: 204800                     # 200 KB
    claim-check-enabled: false
    claim-check-s3-bucket: ${CLAIM_CHECK_BUCKET:}
```

### Appendix B: Sample Database DDL (PostgreSQL 15+)

```sql
-- Audit table for message lifecycle tracking
CREATE TABLE message_audit (
    id                BIGSERIAL PRIMARY KEY,
    message_id        VARCHAR(255)   NOT NULL UNIQUE,
    correlation_id    VARCHAR(255),
    source_destination VARCHAR(512)  NOT NULL,
    consumer_group    VARCHAR(255)   NOT NULL,
    message_payload   JSONB,
    payload_size_bytes INTEGER       NOT NULL,
    payload_hash      VARCHAR(64),
    sns_message_id    VARCHAR(255),
    sns_topic_arn     VARCHAR(512),
    status            VARCHAR(50)    NOT NULL DEFAULT 'RECEIVED',
    retry_count       INTEGER        NOT NULL DEFAULT 0,
    error_message     TEXT,
    received_at       TIMESTAMP WITH TIME ZONE NOT NULL,
    processed_at      TIMESTAMP WITH TIME ZONE,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Performance indexes
CREATE INDEX idx_audit_message_id        ON message_audit(message_id);
CREATE INDEX idx_audit_correlation_id    ON message_audit(correlation_id);
CREATE INDEX idx_audit_status            ON message_audit(status);
CREATE INDEX idx_audit_created_at        ON message_audit(created_at);
CREATE INDEX idx_audit_received_at       ON message_audit(received_at);
CREATE INDEX idx_audit_source_dest       ON message_audit(source_destination);

-- Outbox table for transactional messaging (SNS FIFO)
CREATE TABLE message_outbox (
    id                BIGSERIAL PRIMARY KEY,
    aggregate_id      VARCHAR(255)            NOT NULL,
    event_type        VARCHAR(100)            NOT NULL,
    payload           JSONB                   NOT NULL,
    destination_name  VARCHAR(512)            NOT NULL,
    target_sns_arn    VARCHAR(512)            NOT NULL,
    message_group_id  VARCHAR(128)            NOT NULL,
    deduplication_id  VARCHAR(128)            NOT NULL UNIQUE,
    status            VARCHAR(20)             NOT NULL DEFAULT 'PENDING',
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    published_at      TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_outbox_status     ON message_outbox(status);
CREATE INDEX idx_outbox_created_at ON message_outbox(created_at);
CREATE INDEX idx_outbox_dest       ON message_outbox(destination_name);

-- Trigger for auto-updating updated_at on audit table
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_message_audit_updated_at
    BEFORE UPDATE ON message_audit
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- LISTEN/NOTIFY trigger for near-real-time outbox processing
CREATE OR REPLACE FUNCTION notify_outbox_insert()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('outbox_channel', NEW.id::text);
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER outbox_insert_notify
    AFTER INSERT ON message_outbox
    FOR EACH ROW
    EXECUTE FUNCTION notify_outbox_insert();
```

### Appendix C: IAM Policy Example (Least Privilege — Used via IRSA)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSIAMAuth",
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:db-instance-resource-id/hermes_app"
    },
    {
      "Sid": "SNSFIFOPublish",
      "Effect": "Allow",
      "Action": ["sns:Publish", "sns:PublishBatch"],
      "Resource": "arn:aws:sns:us-east-1:123456789012:hermes-*.fifo"
    },
    {
      "Sid": "SecretsManagerRead",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:hermes/*"
    },
    {
      "Sid": "KMSDecrypt",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "arn:aws:kms:us-east-1:123456789012:key/hermes-cmk-id"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": "*",
      "Condition": {
        "StringEquals": { "cloudwatch:namespace": "CAGHermes" }
      }
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:us-east-1:123456789012:log-group:/rosa/hermes-*:*"
    },
    {
      "Sid": "XRay",
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMParameterRead",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParameters"],
      "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/hermes/*"
    },
    {
      "Sid": "S3ClaimCheck",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::hermes-claim-check-bucket/*",
      "Condition": {
        "StringEquals": { "s3:x-amz-server-side-encryption": "aws:kms" }
      }
    }
  ]
}
```

> **IRSA Trust Policy:** The IAM role's trust policy SHALL allow `sts:AssumeRoleWithWebIdentity` from the ROSA cluster's OIDC provider, scoped to the specific Kubernetes ServiceAccount and namespace.

### Appendix D: Security Group and NetworkPolicy Rules

**ROSA Worker Node Security Group**

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|--------------------|---------|
| Outbound | TCP | 55443 | Solace Broker IPs (via NAT GW) | SMF over TLS |
| Outbound | TCP | 943 | Solace Broker IPs (via NAT GW) | SEMP over TLS (monitoring) |
| Outbound | TCP | 5432 | RDS Security Group | PostgreSQL |
| Outbound | TCP | 443 | VPC Endpoint SGs | AWS services via PrivateLink |
| Inbound/Outbound | Various | Various | ROSA cluster SG (self) | Intra-cluster communication (managed by ROSA) |
| Inbound | None | - | Internet | No inbound internet access to workers |

**VPC Endpoint Security Group**

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|--------------------|---------|
| Inbound | TCP | 443 | ROSA Worker Node SG | AWS API calls from pods |

**RDS Security Group**

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|--------------------|---------|
| Inbound | TCP | 5432 | ROSA Worker Node SG | PostgreSQL from pods |
| Outbound | None | - | - | No outbound required |

**Kubernetes NetworkPolicy (hermes namespace)**

```yaml
# Default deny all ingress and egress in hermes namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: hermes
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress

---
# Allow hermes pods to reach required endpoints
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: hermes-app-egress
  namespace: hermes
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: hermes
  policyTypes:
    - Egress
  egress:
    # DNS resolution (CoreDNS)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-dns
      ports:
        - protocol: UDP
          port: 5353
        - protocol: TCP
          port: 5353
    # RDS PostgreSQL (VPC CIDR)
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8    # Adjust to VPC CIDR
      ports:
        - protocol: TCP
          port: 5432
    # Solace broker (public IPs via NAT GW)
    - to:
        - ipBlock:
            cidr: <solace-broker-ip>/32
      ports:
        - protocol: TCP
          port: 55443
        - protocol: TCP
          port: 943
    # AWS VPC Endpoints (HTTPS)
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8    # VPC CIDR covers endpoint ENIs
      ports:
        - protocol: TCP
          port: 443
```

### Appendix E: Helm Values Example (Per-Destination)

```yaml
# values-prod-orders.yaml
global:
  environment: production
  namespace: hermes

image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/hermes
  tag: "1.2.3"
  pullPolicy: IfNotPresent

serviceAccount:
  name: hermes-orders
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/hermes-orders-irsa"

deployment:
  name: hermes-orders
  replicas: 2
  resources:
    requests:
      cpu: "1"
      memory: "2Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
  terminationGracePeriodSeconds: 60

autoscaling:
  hpa:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
  keda:
    enabled: true
    triggers:
      - type: aws-cloudwatch
        metadata:
          namespace: CAGHermes
          expression: "SELECT MAX(outbox.pending.count) FROM CAGHermes WHERE Destination = 'orders'"
          targetMetricValue: "50"

solace:
  destination: "orders/events"
  destinationType: "QUEUE"
  targetSnsArn: "arn:aws:sns:us-east-1:123456789012:hermes-orders.fifo"
  messageGroupStrategy: "CORRELATION_HASH"
  messageGroupPartitions: 10
  maxPayloadSizeBytes: 204800
  prefetch: 32                 # Reduced from 256 for transactional processing (SOL-FINDING-003)
  concurrency: 16
  ackMode: INDIVIDUAL           # INDIVIDUAL_ACKNOWLEDGE — required for concurrent processing (SOL-FINDING-011)

probes:
  liveness:
    path: /actuator/health/liveness
    port: 8081
    initialDelaySeconds: 30
    periodSeconds: 10
  readiness:
    path: /actuator/health/readiness
    port: 8081
    initialDelaySeconds: 15
    periodSeconds: 5
  startup:
    path: /actuator/health
    port: 8081
    failureThreshold: 30
    periodSeconds: 10

podDisruptionBudget:
  minAvailable: 1

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule

externalSecrets:
  - name: solace-credentials
    secretStore: aws-secrets-manager
    remoteRef: hermes/solace/orders
  - name: truststore
    secretStore: aws-secrets-manager
    remoteRef: hermes/tls/truststore
```

### Appendix F: Destination Onboarding Checklist

When adding a new Solace destination to the system:

1. **Solace Broker-Side Provisioning (Section 3.8)**
   - [ ] Confirm destination type (topic or queue) and name with Solace team
   - [ ] Provision Solace queue (`hermes.{destination}`) per Section 3.8.2 spec
   - [ ] Configure topic-to-queue subscriptions if topic-based (Section 3.8.3)
   - [ ] Verify client profile connection limit accommodates additional pods
   - [ ] Configure queue spool limits, TTL, max-redelivery-count (10)
   - [ ] Configure Solace-side DMQ with matching redelivery settings
   - [ ] Update ACL profile to allow topic subscription for new destination
   - [ ] Verify all NAT Gateway EIPs are whitelisted
   - [ ] Validate SEMP monitoring metrics for new queue

2. **AWS Infrastructure (Terraform)**
   - [ ] Add destination to Terraform variables
   - [ ] Create SNS FIFO topic (or reuse existing) with encryption
   - [ ] Create SQS FIFO queues and DLQs for downstream consumers
   - [ ] Create IAM role for the destination's ServiceAccount (IRSA)
   - [ ] Store destination-specific secrets in Secrets Manager
   - [ ] Store destination configuration in Parameter Store
   - [ ] Configure CloudWatch Alarms for new destination
   - [ ] Update CloudWatch Dashboard with new destination panels

3. **OpenShift / Helm (Git)**
   - [ ] Create Helm values file for the destination (`values-{env}-{destination}.yaml`)
   - [ ] Configure ExternalSecret manifests to sync credentials from Secrets Manager
   - [ ] Configure ServiceAccount with IRSA annotation
   - [ ] Set HPA/KEDA scaling parameters
   - [ ] Configure NetworkPolicy egress rules if destination-specific IPs differ
   - [ ] Deploy via Helm to staging, validate, then promote to production

4. **Validation**
   - [ ] Run integration tests with Testcontainers
   - [ ] Run abbreviated performance smoke test
   - [ ] Verify metrics appear in CloudWatch dashboard (via ADOT)
   - [ ] Verify alerts fire correctly (test with synthetic failure)
   - [ ] Verify pod anti-affinity distributes across AZs
   - [ ] Document data classification for the destination's message payloads

---

*End of Requirements Document*

*Document prepared for CAG Hermes project. All requirements are subject to review and approval by project stakeholders.*
