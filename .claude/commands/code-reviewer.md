# Code Reviewer

Review the most recently generated code against all coding standards defined in CLAUDE.md for the Containers with Middleware project. Produce a **detailed structured checklist** that is precise enough for an AI tool to understand each issue and exactly how to fix it. At the end, ask the user whether to proceed with corrections.

## Instructions

You are reviewing Java / Spring Boot code for the Containers with Middleware project. The project uses Java 17, Spring Boot 3.5.x, JCSMP, Resilience4j 2.4.0, Testcontainers 2.0.4, and PostgreSQL via RDS. All standards are in CLAUDE.md.

Work through every section below in order. For each item, determine PASS, FAIL, or N/A. For every FAIL, write a detailed finding entry (see format below).

---

## Section 1 — Java & Spring Boot Standards

Check each rule:

1. **Java version features**: Does the code use Java 17 constructs where appropriate?
   - Records used for immutable DTOs instead of POJO classes with getters/setters
   - Sealed classes used where a closed type hierarchy exists
   - Text blocks used for multi-line SQL strings instead of string concatenation
   - Pattern matching for instanceof used instead of explicit casts

2. **Transaction boundaries**: Are all public service method transaction boundaries explicit?
   - Every public method in a `@Service` class that touches the DB must have `@Transactional` declared explicitly
   - No reliance on implicit/inherited transactions from callers
   - `readOnly = true` set on read-only transaction methods

3. **Dependency injection**: Is constructor injection used exclusively?
   - No `@Autowired` on fields — only on constructors or not at all (single-constructor implicit injection)
   - No `@Autowired` on setter methods
   - All injected fields declared `private final`

4. **Exception handling**: Are exceptions handled correctly?
   - No empty catch blocks (`catch (Exception e) {}`)
   - No catch-and-swallow patterns (catch, log nothing, continue as if nothing happened)
   - Every caught exception must be logged with structured context (`correlationId`, `messageId`, `destination`) before rethrowing or routing to DLQ
   - No `printStackTrace()` calls

5. **Logging**: Is structured JSON logging used correctly?
   - `@Slf4j` (Lombok) used — no `LoggerFactory.getLogger(...)` boilerplate
   - No `System.out.println` or `System.err.println`
   - Log level selection: `DEBUG` for message lifecycle events, `INFO` for state transitions, `WARN` for recoverable errors, `ERROR` for failures requiring attention
   - Every log statement at WARN or above includes `correlationId`, `messageId`, `destination` in structured fields (MDC or structured arguments — not string concatenation)
   - No secrets, PII, or full message payloads logged

6. **Configuration**: Is all configuration externalised?
   - No hardcoded strings for hostnames, ports, queue names, topic names, ARNs, account IDs, region strings
   - No hardcoded numeric values that should be tunable (timeouts, pool sizes, retry counts)
   - All config references map to `application.yml` properties or environment variables

7. **Test coverage**: Does the code have a corresponding unit test?
   - Every new public class has a corresponding test class in `src/test`
   - Happy path tested
   - At least one failure/edge-case path tested

---

## Section 2 — Solace / JCSMP Standards

Check each rule (mark N/A if the code does not touch Solace):

1. **ACK mode**: Is `INDIVIDUAL_ACKNOWLEDGE` mode used?
   - `JCSMPProperties.MESSAGE_ACK_MODE` set to `JCSMPProperties.SUPPORTED_MESSAGE_ACK_MANUAL` (INDIVIDUAL_ACK)
   - No use of `CLIENT_ACK` or auto-ack mode

2. **ACK timing**: Is the message acknowledged only after the DB transaction commits?
   - `message.ackMessage()` called only inside the success path, after `@Transactional` method returns without exception
   - No ACK call inside the `@Transactional` boundary
   - No ACK call in a `finally` block that runs regardless of success/failure

3. **FlowReceiver backpressure**: Is the FlowReceiver stopped/started with circuit breaker state?
   - `FlowReceiver.stop()` called in the circuit breaker `onOpen` callback
   - `FlowReceiver.start()` called in the circuit breaker `onClose` callback

4. **Reconnect retries**: Is infinite reconnect configured?
   - `reconnectRetries` set to `-1`
   - No finite positive value set for `reconnectRetries` anywhere

5. **Client name**: Does the client name include the pod UID?
   - Pattern: `aws-hermes-{destination}-{pod-uid}`
   - No static client names that would cause collisions during rolling updates

6. **Prefetch window**: Is `sub-ack-window-size` set to 32?
   - `SUPPORTED_SUB_ACK_WINDOW_SIZE` or equivalent set to `32`
   - No value above 32 without explicit comment referencing load test validation

---

## Section 3 — Transactional Outbox Standards

Check each rule (mark N/A if the code does not touch the outbox):

1. **Single transaction**: Are audit write and outbox write in a single `@Transactional` method?
   - Both `auditMessageRepository.save(...)` and `outboxMessageRepository.save(...)` called within the same `@Transactional` method
   - No separate transactions — they must commit or rollback together
   - No `@Transactional(propagation = REQUIRES_NEW)` separating the two writes

2. **SKIP LOCKED**: Does the outbox poller use `SELECT ... FOR UPDATE SKIP LOCKED`?
   - Native query or JPQL with `SKIP LOCKED` hint used
   - No plain `findAll()` or `findByStatus()` without locking

3. **LISTEN/NOTIFY + fallback poll**: Are both trigger mechanisms present?
   - PostgreSQL LISTEN/NOTIFY connection and handler present
   - 500ms fallback `@Scheduled` poll also present — not replaced by LISTEN/NOTIFY
   - Both must coexist

4. **Outbox status transitions**: Are status transitions correct?
   - `PENDING` → `PUBLISHED` on success
   - `PENDING` → `FAILED` on error (with retry)
   - `FAILED` → `DLQ` after retry exhaustion
   - No direct `PENDING` → `DLQ` without retries
   - No other status values used

---

## Section 4 — Resilience Standards

Check each rule (mark N/A if the code does not involve RDS writes, SNS publishes, or thread pools):

1. **Circuit breakers**: Are circuit breakers applied to the correct operations?
   - Circuit breaker wrapping RDS write operations
   - Circuit breaker wrapping SNS publish operations
   - No other operations using circuit breakers not defined in ResilienceConfig

2. **Retry configuration**: Is retry with exponential backoff + jitter used where required?
   - SNS publish retried with exponential backoff + jitter
   - S3 upload retried with exponential backoff + jitter
   - No linear/fixed-interval retry used

3. **Retry placement**: Is retry wrapping the transaction (not inside it)?
   - `@Retry` annotation or programmatic retry applies to a method that calls the `@Transactional` method
   - `@Retry` is NOT on the same method as `@Transactional`
   - No retry loop coded inside a `@Transactional` method body

4. **Bulkheads**: Are separate thread pools used for each concern?
   - Solace consumption runs in its own thread pool
   - RDS writes run in their own thread pool
   - SNS publishes run in their own thread pool
   - No shared executor across concerns

---

## Section 5 — Infrastructure Code (Terraform / Helm)

Check each rule (mark N/A if the code is not Terraform or Helm):

1. **Required tags**: Do all Terraform resources have the 5 mandatory tags?
   - `Project`, `Environment`, `Owner`, `CostCenter`, `Destination` present on every `resource` block

2. **No hardcoded values**: Are all Terraform modules parameterised?
   - No hardcoded ARNs, account IDs, or region strings inside module files
   - All such values passed as input variables

3. **RDS Proxy**: Is `enable_rds_proxy = true` set?
   - `enable_rds_proxy` variable present and defaulting to `true`
   - Not conditionally disabled

4. **KMS CMKs**: Are CMKs used for all required services?
   - KMS CMK references for RDS, SNS, SQS, S3, Secrets Manager — no AWS-managed keys

5. **Helm probes**: Does the Deployment have all 3 probes and resource limits?
   - `livenessProbe`, `readinessProbe`, `startupProbe` all present
   - `resources.requests` and `resources.limits` both set (CPU + memory)
   - `podAntiAffinity` configured across AZs

6. **No secrets in values files**: Are values files free of secrets?
   - No passwords, tokens, keys, or certificates in any `values*.yaml` file
   - Secrets sourced via `ExternalSecret` CRD referencing Secrets Manager

---

## Output Format

For each FAIL, produce a finding in this exact format:

```
❌ [SECTION] — [RULE NAME]
   Issue    : <Precise description of what is wrong in the code, including the file name and line number if visible>
   Why      : <Why this is a problem — the risk or violation it causes>
   Fix      : <Exact, step-by-step instruction on what to change, including the exact code pattern to replace and what to replace it with>
   Example  : <A before/after code snippet illustrating the fix, if applicable>
```

For each PASS, produce a single line:
```
✅ [SECTION] — [RULE NAME]
```

For each N/A, produce a single line:
```
⬜ [SECTION] — [RULE NAME] — Not applicable (no Solace/outbox/Terraform code in scope)
```

---

## Summary Table

After the full checklist, produce this summary:

```
## Review Summary
| Category              | PASS | FAIL | N/A |
|-----------------------|------|------|-----|
| Java & Spring Boot    |      |      |     |
| Solace / JCSMP        |      |      |     |
| Transactional Outbox  |      |      |     |
| Resilience            |      |      |     |
| Infrastructure        |      |      |     |
| TOTAL                 |      |      |     |

Overall: [PASS / FAIL]
```

---

## Proceed Prompt

After the summary, always end with:

```
---
Shall I proceed with correcting all FAIL items above? (Yes / No)

If Yes, I will apply all fixes in sequence, re-running this checklist after each fix to confirm resolution.
If No, the findings above are saved for your reference and no changes will be made.
```
