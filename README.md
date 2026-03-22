# Containers with Middleware

A production-grade, resilient Solace-to-AWS messaging bridge running on ROSA (Red Hat OpenShift on AWS).

**Message flow:**
```
Solace PubSub+ → JCSMP FlowReceiver → RDS PostgreSQL (audit + outbox, 1 TX) → ACK → Outbox Poller → SNS FIFO → SQS FIFO
```

**MVP destination:** `flightschedules`

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | 4.x+ | [docker.com](https://www.docker.com/products/docker-desktop) |
| Java | 17.0.18 (Temurin) | `winget install EclipseAdoptium.Temurin.17.JDK` |
| Maven | 3.9.14 | Bundled via `./mvnw` wrapper |
| Terraform | 1.14.7 | `winget install HashiCorp.Terraform` |
| Helm | 4.1.3 | `winget install Helm.Helm` |

---

## Local Development Stack

The local stack runs the full message pipeline on your laptop — no AWS credentials required.

**Services started:**

| Service | Image | Port(s) | Purpose |
|---|---|---|---|
| Solace PubSub+ Standard | `solace/solace-pubsub-standard:latest` | 55555, 55443, 8080 | Message broker |
| PostgreSQL | `postgres:15.17` | 5432 | Audit + outbox database |
| LocalStack | `localstack/localstack:4.14` | 4566 | Local AWS (SNS, SQS, S3, SSM, Secrets Manager) |

### First-time setup

```bash
# 1. Create your local environment file
cp local-dev/.env.example local-dev/.env

# 2. Review local-dev/.env and adjust any values if needed
#    Default values work out of the box for local development

# 3. Start the stack
cd local-dev
docker compose up -d

# 4. Verify all services are healthy
docker compose ps
```

All three services must show `healthy` before running the application.

### Service access

| Service | URL / Connection | Credentials |
|---|---|---|
| Solace Admin UI | http://localhost:8080 | admin / admin |
| Solace SMF (plaintext) | tcp://localhost:55555 | — |
| Solace SMF (TLS) | tcps://localhost:55443 | — |
| PostgreSQL | localhost:5432 / db: hermes | hermes / hermes |
| LocalStack | http://localhost:4566 | test / test (not validated) |

### Useful commands

```bash
# Check health of all services
docker compose ps

# Tail logs for all services
docker compose logs -f

# Tail logs for a specific service
docker compose logs -f solace
docker compose logs -f postgres
docker compose logs -f localstack

# Stop all services (keeps volumes — data persists)
docker compose down

# Stop all services AND remove all data volumes (full reset)
docker compose down -v

# Restart a single service
docker compose restart postgres
```

### LocalStack AWS services

LocalStack simulates the following AWS services locally:

| Service | Endpoint |
|---|---|
| SNS | http://localhost:4566 |
| SQS | http://localhost:4566 |
| S3 | http://localhost:4566 |
| Secrets Manager | http://localhost:4566 |
| SSM Parameter Store | http://localhost:4566 |

Use AWS CLI with LocalStack:
```bash
aws --endpoint-url=http://localhost:4566 sns list-topics
aws --endpoint-url=http://localhost:4566 sqs list-queues
aws --endpoint-url=http://localhost:4566 s3 ls
```

> LocalStack does not validate AWS credentials in community mode.
> Use `AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test` or set them in `.env`.

### ⚠ LocalStack auth notice

LocalStack enforces authentication for the free tier from **2026-03-23**.
The current setup uses community edition without an auth token, which may stop working after that date.

**To enable auth (5-minute change):**
1. Obtain a free token at https://app.localstack.cloud/
2. In `local-dev/.env`, uncomment and set: `LOCALSTACK_AUTH_TOKEN=<your-token>`
3. In `local-dev/docker-compose.yml`, uncomment: `# LOCALSTACK_AUTH_TOKEN: ${LOCALSTACK_AUTH_TOKEN}`
4. Restart LocalStack: `docker compose restart localstack`

---

## Publishing Test Messages (SDKPerf)

[SDKPerf](https://solace.com/downloads/) is Solace's performance test tool and the simplest way to publish messages into the local broker without running the full application.

### Download SDKPerf

1. Go to https://solace.com/downloads/ → **Other Downloads** → **SDKPerf**
2. Download the Java edition (`sdkperf-java-<version>.zip`)
3. Extract to a convenient directory (e.g. `C:\tools\sdkperf`)
4. On Windows: use `sdkperf_java.bat` — on Linux/macOS: use `sdkperf_java`

> The local Solace broker must be running (`docker compose up -d`) before publishing.
> Confirm the broker is healthy: `docker compose ps` — solace must show `healthy`.

### Verify the queue is provisioned

Check that `hermes-solace-init` ran successfully before publishing:

```bash
# Should show [OK] or [SKIP] for all 3 resources
docker compose logs hermes-solace-init
```

Then confirm the queue exists via the Solace Admin UI:
**http://localhost:8080** → Messaging → Queues → `hermes.flightschedules`

---

### Publish 10 standard test messages

```bash
# Windows
sdkperf_java.bat -cip=tcp://localhost:55555 -cu=admin@default -cp=admin ^
  -pql=flightschedules/events -mn=10 -mr=1 -msa=1024

# Linux / macOS
./sdkperf_java -cip=tcp://localhost:55555 -cu=admin@default -cp=admin \
  -pql=flightschedules/events -mn=10 -mr=1 -msa=1024
```

| Flag | Value | Meaning |
|------|-------|---------|
| `-cip` | `tcp://localhost:55555` | Broker SMF plaintext endpoint |
| `-cu` | `admin@default` | Username @ Message VPN |
| `-cp` | `admin` | Password |
| `-pql` | `flightschedules/events` | Topic to publish to — matched by the `flightschedules/>` subscription |
| `-mn` | `10` | Total messages to publish |
| `-mr` | `1` | Rate: 1 message/second |
| `-msa` | `1024` | Message size: 1 KB |

---

### Publish large messages (>200 KB — triggers claim-check path)

Messages exceeding 200 KB will be stored in S3 and replaced with a claim-check reference by the consumer application.

```bash
# Windows — 5 messages at 250 KB each
sdkperf_java.bat -cip=tcp://localhost:55555 -cu=admin@default -cp=admin ^
  -pql=flightschedules/events -mn=5 -mr=1 -msa=256000

# Linux / macOS
./sdkperf_java -cip=tcp://localhost:55555 -cu=admin@default -cp=admin \
  -pql=flightschedules/events -mn=5 -mr=1 -msa=256000
```

> **Claim-check threshold:** 200 KB = 204,800 bytes. `-msa=256000` (250 KB) reliably exceeds it.

---

### Verify messages arrived in the queue

After publishing, confirm messages are queued:

```bash
# Check queue depth via Solace Admin UI
# http://localhost:8080 → Messaging → Queues → hermes.flightschedules → Messages Spooled

# Or check via SEMP v2 API:
curl -s -u admin:admin \
  "http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/hermes.flightschedules" \
  | grep -o '"msgSpoolUsage":[0-9]*'
```

---

## Running the Application Locally

```bash
# Generate local mTLS certificates first (US-E0-002)
./local-dev/certs/generate-certs.sh

# Start the application with the local profile
./mvnw spring-boot:run -Dspring-boot.run.profiles=local
```

---

## Running Tests

```bash
# Unit tests only (no Docker required)
./mvnw test

# Integration tests (requires Docker — Testcontainers spins up containers)
./mvnw verify -P integration-tests
```

---

## Infrastructure

```bash
# Terraform plan — staging environment
cd infra/terraform/environments/staging
terraform init && terraform plan

# Helm dry-run — staging
helm upgrade --install hermes-flightschedules ./helm/hermes \
  -f helm/hermes/values-staging.yaml \
  --dry-run --debug
```

---

## Project Documentation

| Document | Description |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Coding standards, architecture decisions, Definition of Done |
| [project-plan.md](project-plan.md) | Sprint roadmap and epics |
| [backlog.md](backlog.md) | User stories and acceptance criteria |
| [requirements.md](requirements.md) | Detailed requirements specification |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [docs/runbooks/](docs/runbooks/) | Operational runbooks |
| [dev-journal/](dev-journal/) | Development progress journal (story-by-story) |
