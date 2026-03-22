# Development Progress Index
Last updated: 2026-03-22

| Story ID    | Title                                                     | Status  | Sprint | Journal |
|-------------|-----------------------------------------------------------|---------|--------|---------|
| US-E0-001   | Docker Compose stack for local development                | COMPLETE | 1      | dev-journal/E0-001.md |
| US-E0-002   | Self-signed mTLS certificate generation for local Solace  | COMPLETE | 1      | dev-journal/E0-002.md |
| US-E0-003   | LocalStack initialisation for SNS FIFO and SQS FIFO       | COMPLETE | 1      | dev-journal/E0-003.md |
| US-E0-004   | Solace local queue and subscription provisioning          | COMPLETE | 1      | dev-journal/E0-004.md |
| US-E0-005   | Spring Boot local application profile                     | PENDING | 1      | —       |
| US-E1-001   | Terraform remote state backend                            | PENDING | 1      | —       |
| US-E1-002   | VPC and networking module                                 | PENDING | 1      | —       |
| US-E1-003   | VPC Interface Endpoints                                   | PENDING | 2      | —       |
| US-E1-004   | KMS Customer Managed Keys                                 | PENDING | 2      | —       |
| US-E1-005   | ROSA cluster provisioning                                 | PENDING | 2      | —       |
| US-E1-006   | ECR repository and image scanning                         | PENDING | 1      | —       |
| US-E1-007   | S3 buckets for logs and archives                          | PENDING | 1      | —       |
| US-E2-001   | Secrets Manager secrets for Solace credentials            | PENDING | 2      | —       |
| US-E2-002   | IAM roles and IRSA configuration                          | PENDING | 2      | —       |
| US-E2-003   | External Secrets Operator configuration                   | PENDING | 2      | —       |
| US-E2-004   | OpenShift namespace security (SCCs, RBAC, NetworkPolicies)| PENDING | 3      | —       |
| US-E2-005   | RDS Secrets Manager and IAM database auth                 | PENDING | 3      | —       |
| US-E3-001   | RDS PostgreSQL Multi-AZ Terraform module                  | PENDING | 2      | —       |
| US-E3-002   | Database schema migration — audit_messages table          | PENDING | 3      | —       |
| US-E3-003   | Database schema migration — outbox_messages + trigger     | PENDING | 3      | —       |
| US-E3-004   | HikariCP connection pool configuration                    | PENDING | 3      | —       |
| US-E4-001   | SNS FIFO topic for flightschedules                        | PENDING | 3      | —       |
| US-E4-002   | SQS FIFO queues and DLQ for flightschedules               | PENDING | 3      | —       |
| US-E4-003   | SNS/SQS message group strategy configuration              | PENDING | 3      | —       |
| US-E5-001   | Spring Boot project scaffold                              | PENDING | 3      | —       |
| US-E5-002   | JCSMP FlowReceiver with mTLS configuration                | PENDING | 3–4    | —       |
| US-E5-003   | Solace SessionEventHandler and reconnection lifecycle     | PENDING | 4      | —       |
| US-E5-004   | Structured JSON logging baseline                          | PENDING | 4      | —       |
| US-E6-001   | FlightSchedule canonical data model and deserialisation   | PENDING | 4      | —       |
| US-E6-002   | Message validation (schema + size check)                  | PENDING | 4      | —       |
| US-E6-003   | Idempotent consumer — duplicate detection                 | PENDING | 4      | —       |
| US-E6-004   | Transactional Outbox — single database transaction        | PENDING | 4      | —       |
| US-E6-005   | Outbox poller with LISTEN/NOTIFY and fallback polling     | PENDING | 4–5    | —       |
| US-E6-006   | SNS FIFO publish from outbox poller                       | PENDING | 5      | —       |
| US-E7-001   | Large message detection and S3 storage                    | PENDING | 5      | —       |
| US-E7-002   | Claim-check reference in SNS message                      | PENDING | 5      | —       |
| US-E8-001   | Circuit breakers for RDS and SNS                          | PENDING | 5      | —       |
| US-E8-002   | Retry with exponential backoff and jitter                 | PENDING | 5      | —       |
| US-E8-003   | Bulkhead — separate thread pools                          | PENDING | 6      | —       |
| US-E8-004   | DLQ routing for persistently failing messages             | PENDING | 6      | —       |
| US-E8-005   | Graceful shutdown (SIGTERM handler)                       | PENDING | 6      | —       |
| US-E9-001   | Helm chart scaffold                                       | PENDING | 6      | —       |
| US-E9-002   | Kubernetes probes and resource configuration              | PENDING | 6      | —       |
| US-E9-003   | Pod anti-affinity and topology spread                     | PENDING | 6      | —       |
| US-E9-004   | HPA and KEDA auto-scaling                                 | PENDING | 7      | —       |
| US-E9-005   | ConfigMaps and ExternalSecrets in Helm                    | PENDING | 6      | —       |
| US-E10-001  | ADOT Collector DaemonSet deployment                       | PENDING | 7      | —       |
| US-E10-002  | Custom CloudWatch metrics via Micrometer                  | PENDING | 7      | —       |
| US-E10-003  | CloudWatch Alarms                                         | PENDING | 7      | —       |
| US-E10-004  | X-Ray distributed tracing                                 | PENDING | 7      | —       |
| US-E10-005  | CloudWatch Dashboard                                      | PENDING | 8      | —       |
| US-E11-001  | AWS CodePipeline and CodeBuild setup                      | PENDING | 8      | —       |
| US-E11-002  | Testcontainers integration test suite                     | PENDING | 8      | —       |
| US-E12-001  | Load test environment setup                               | PENDING | 9      | —       |
| US-E12-002  | Baseline, burst, and endurance tests                      | PENDING | 9      | —       |
| US-E12-003  | Failure and recovery tests                                | PENDING | 9      | —       |
| US-E13-001  | Multi-AZ failover validation                              | PENDING | 9      | —       |
| US-E13-002  | DR and operational runbooks                               | PENDING | 10     | —       |
| US-E13-003  | Production go-live checklist                              | PENDING | 10     | —       |
