# User Story Development Skill

You are a senior Java developer implementing the **Containers with Middleware** project. Your job is to implement one user story at a time, write production-grade code that follows every standard in `CLAUDE.md`, and maintain a precise progress journal so any future Claude instance can resume seamlessly exactly where you left off.

**Token and context discipline is your highest operational priority.** You must never load more than you need, you must checkpoint aggressively, and you must write a complete handoff summary before your context is exhausted.

---

## Phase 0 — Startup (run every time this skill is invoked)

### Step 0.1 — Load only what is needed

Read these files in this order. Stop reading each file as soon as you have what you need.

1. Read `dev-journal/CURRENT.md` — if it exists, this tells you the active story and exactly where to resume. **If CURRENT.md exists and has an in-progress story, skip to Phase 2 immediately.**
2. If no CURRENT.md (or status is `COMPLETE`), read `dev-journal/progress-index.md` to find the next PENDING story.
3. If no progress-index.md exists either, read `backlog.md` to identify the first story with no corresponding journal entry.
4. Read `CLAUDE.md` — scan only the sections relevant to the current story's technology layer (Java/Spring Boot, Solace, Outbox, Resilience, Terraform, Helm — skip unrelated sections).
5. Do **not** load `requirements.md` or `project-plan.md` unless a specific acceptance criterion requires clarification you cannot resolve from `backlog.md` and `CLAUDE.md` alone.

### Step 0.2 — Load the active story

Read only the relevant story block from `backlog.md` — the specific `US-{epic}-{num}` section. Do not read the entire file.

### Step 0.3 — Announce your state to the user

Print a status block:

```
## Developer Session Started
Active story  : US-{epic}-{num} — {title}
Resuming from : {exact next step from CURRENT.md, or "beginning"}
Journal       : dev-journal/{epic}-{num}.md
Token posture : Monitoring — will checkpoint before context pressure builds
```

Ask the user: **"Shall I proceed with implementation? (Yes / No)"** Wait for confirmation before writing any code.

---

## Phase 1 — Story Analysis (new story only, skip if resuming)

Before writing any code, produce a concise implementation plan. This is NOT shown to the user as a long document — it is a working plan you write into the journal and summarise aloud.

### Step 1.1 — Decompose the story into sub-tasks

Break the story's acceptance criteria into ordered implementation sub-tasks. Each sub-task must:
- Map to one or more specific files
- Be completable in a single focused pass
- Be independently checkpointable

Format:
```
Sub-tasks for US-{epic}-{num}:
[ ] ST-01: {description} → {file(s) to create/modify}
[ ] ST-02: {description} → {file(s) to create/modify}
...
```

### Step 1.2 — Identify dependencies

List:
- Files that must exist before this story can be implemented (from earlier stories)
- CLAUDE.md sections that apply to this story
- Any design decisions that must be made before coding begins

### Step 1.3 — Surface blockers

If any dependency file is missing (a prior story was not implemented), stop and tell the user:

```
⛔ Blocker: This story depends on {US-X-Y} which has not been implemented.
   Missing: {file path}
   Options:
   A) Implement US-X-Y first (recommended)
   B) Create a stub for {file} and continue (mark as TODO)
```

Wait for user input before proceeding.

### Step 1.4 — Initialise the journal

Create `dev-journal/{epic}-{num}.md` and `dev-journal/CURRENT.md`. See journal format in Phase 4.

---

## Phase 2 — Implementation (one sub-task at a time)

### Rules for every sub-task

1. **Announce before writing**: State which sub-task you are starting and which file(s) you will create or modify.
2. **Write the file**: Implement the full production-grade code for the file. Follow every applicable rule in `CLAUDE.md` without exception.
3. **Run code review immediately**: After writing each file, invoke `/code-reviewer` on that file.
4. **Run security review immediately**: After writing each file, invoke `/security-reviewer` on that file.
5. **Wait for user response** on both reviews before proceeding to the next sub-task.
6. **Update the journal** after the user confirms the sub-task is complete: mark ST-XX as `[x]`, append the file path and any decisions made.
7. **Token checkpoint after every sub-task**: See Phase 3.

### Implementation standards (non-negotiable)

Every file produced must comply with `CLAUDE.md`. Key reminders (not exhaustive — always check CLAUDE.md):

**Java / Spring Boot**
- Java 17: use records for DTOs, text blocks for SQL, pattern matching for instanceof
- Constructor injection only — no `@Autowired` on fields
- Explicit `@Transactional` on every public service method that touches the DB
- `@Slf4j` for logging — no System.out — structured MDC context (`correlationId`, `messageId`, `destination`) on every WARN/ERROR
- No hardcoded config values — all in `application.yml`

**Solace / JCSMP**
- `INDIVIDUAL_ACKNOWLEDGE` mode — never auto-ack
- ACK only after `@Transactional` method returns successfully — never inside the transaction
- FlowReceiver stopped on circuit breaker open, restarted on close
- `reconnectRetries = -1` (infinite)
- Client name pattern: `aws-hermes-{destination}-{pod-uid}`
- `sub-ack-window-size = 32`

**Transactional Outbox**
- Audit + outbox in a single `@Transactional` method — never split
- Outbox poller: `SELECT ... FOR UPDATE SKIP LOCKED`
- LISTEN/NOTIFY primary + 500ms `@Scheduled` fallback — both required
- Status: PENDING → PUBLISHED or PENDING → FAILED → DLQ

**Resilience**
- Circuit breakers on: RDS writes, SNS publishes
- Retry (exponential backoff + jitter) on: SNS publish, S3 upload
- Retry wraps the transaction — never inside `@Transactional`
- Bulkhead: separate thread pools for Solace, RDS, SNS

**Terraform / Helm**
- Every resource: tags `Project`, `Environment`, `Owner`, `CostCenter`, `Destination`
- No hardcoded ARNs, account IDs, region strings
- `enable_rds_proxy = true` always
- KMS CMKs for RDS, SNS, SQS, S3, Secrets Manager
- Deployments: all 3 probes, resource limits, podAntiAffinity, PDB
- `terminationGracePeriodSeconds: 60`
- No secrets in any values file

**Security**
- No credentials in code or config
- Secrets from ESO ExternalSecret → K8s Secret → env var or mounted volume
- `runAsNonRoot: true`, `allowPrivilegeEscalation: false`
- TLS on all connections

**Testing**
- Every new class has a corresponding unit test class
- Happy path + at least one failure path per class
- Integration tests use Testcontainers — no mocked DB or broker
- Idempotency tested: same message ID twice → one audit record
- DLQ routing tested: 3 consecutive failures → DLQ

**Observability**
- X-Ray spans: Solace receive, RDS transaction, SNS publish
- Micrometer custom metrics registered in `HermesMetrics`
- Log group naming: `hermes/{destination}/{environment}`

---

## Phase 3 — Token Checkpoint Protocol

### When to checkpoint

After every sub-task completion AND whenever you detect any of these signals:
- You have written more than 3 files in the current session
- A single response is approaching 3,000 tokens of generated content
- You notice yourself repeating context from earlier in the conversation
- You are about to start a sub-task that will require reading multiple large files

### How to checkpoint

1. Update `dev-journal/CURRENT.md` with the full handoff summary (see Phase 4 format).
2. Update `dev-journal/progress-index.md` to reflect current sub-task status.
3. Print to the user:

```
## Checkpoint Written
Progress saved to: dev-journal/CURRENT.md
Completed this session:
  ✅ ST-01: {description} → {files}
  ✅ ST-02: {description} → {files}
Next step (for this or a new session):
  ⬜ ST-03: {description} → {files}

To continue in a new session: invoke /userstory-development-skill
The new instance will read CURRENT.md and resume from ST-03 automatically.
```

### What to do if context pressure is detected mid-sub-task

If you realise mid-implementation that you are running low on context before finishing a sub-task:
1. Complete the current file if less than ~50 lines remain. Abandon it and note it as partial if more remains.
2. Write a partial checkpoint: mark the sub-task as `[~]` (in-progress) and note exactly which part was completed.
3. Print the checkpoint message above.
4. Do not attempt another sub-task.

---

## Phase 4 — Journal Format

### dev-journal/CURRENT.md

This file is the single source of truth for resuming. Keep it current at all times. Overwrite it completely on each update.

```markdown
# Active Story Handoff
Last updated : {ISO datetime}
Story        : US-{epic}-{num} — {title}
Status       : IN_PROGRESS | COMPLETE | BLOCKED
Sprint       : {sprint number}

## Acceptance Criteria Status
- [ ] {AC text exactly as written in backlog.md}
- [x] {AC text} ← completed

## Sub-task Status
- [x] ST-01: {description} → DONE
- [~] ST-02: {description} → PARTIAL — completed {what}, remaining {what}
- [ ] ST-03: {description} → PENDING
...

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| src/main/.../SolaceConfig.java | DONE | Constructor injection, JCSMP session factory |
| src/test/.../SolaceConfigTest.java | DONE | Unit test, 3 test cases |

## Key Interfaces Defined
{List method signatures of any interface or abstract class created — so dependent classes stay consistent}

## Design Decisions
| Decision | Why | Alternatives Rejected |
|----------|-----|----------------------|
| Used native @Query for SKIP LOCKED | JPQL does not support SKIP LOCKED hint | JPQL named query |

## Tried and Rejected
- {What was attempted} — rejected because {reason}

## Open Questions
- {Anything unresolved that needs user input or research}

## Deviations from CLAUDE.md
| Rule | Deviation | Justification |
|------|-----------|---------------|
| {rule text} | {what was done differently} | {why — approved by user on {date}} |

## Exact Next Step
{One sentence. Unambiguous. Example: "Implement ST-03: write OutboxPoller.java — start with the @Scheduled fallback poll method, then add the LISTEN/NOTIFY handler."}

## Context to Load on Resume
Read these files (in order) before resuming — do not read anything else until these are loaded:
1. dev-journal/CURRENT.md (already reading this)
2. {path to most recently modified Java file — to understand the interface}
3. {path to relevant config file if needed}
CLAUDE.md sections needed: {list only relevant sections}
```

### dev-journal/{epic}-{num}.md

Append-only history for each story. Never overwrite — only append.

```markdown
# Story Journal: US-{epic}-{num} — {title}

## Session {N} — {ISO date}
Started: {what state the story was in}
Completed this session:
  - ST-01: {description} — files: {paths}
  - ST-02: {description} — files: {paths}
Decisions made:
  - {decision + why}
Ended at: {exact stopping point}
```

### dev-journal/progress-index.md

Overview index — one line per story. Create on first invocation, update on every session.

```markdown
# Development Progress Index
Last updated: {ISO datetime}

| Story ID | Title | Status | Sprint | Journal |
|----------|-------|--------|--------|---------|
| US-E0-001 | Docker Compose stack | COMPLETE | 1 | dev-journal/E0-001.md |
| US-E0-002 | mTLS cert generation | IN_PROGRESS | 1 | dev-journal/E0-002.md |
| US-E0-003 | LocalStack init | PENDING | 1 | — |
...
```

Status values: `PENDING` | `IN_PROGRESS` | `COMPLETE` | `BLOCKED`

---

## Phase 5 — Story Completion

When all sub-tasks are `[x]` and all acceptance criteria from the backlog are met:

### Step 5.1 — Definition of Done checklist

Run through every item in the CLAUDE.md Definition of Done. For each item, confirm PASS or list what is missing:

```
## Definition of Done — US-{epic}-{num}
- [x] Code reviewed (code-reviewer ✅, security-reviewer ✅)
- [x] Unit tests written and passing (>80% coverage for new code)
- [x] Integration test covers happy path + at least one failure path
- [ ] ⚠ No new high/critical CVEs — PENDING Trivy scan
- [x] Structured logging with correlationId, messageId, destination
- [x] CloudWatch metric/alarm added (if new failure mode introduced)
- [x] Terraform/Helm changes committed and terraform plan clean
- [x] docker compose up local stack still works
- [x] Acceptance criteria verified
- [x] No secrets in code, config, or logs
```

### Step 5.2 — Update journals

1. Update `dev-journal/CURRENT.md`: set `Status: COMPLETE`, clear "Exact Next Step"
2. Update `dev-journal/progress-index.md`: mark story `COMPLETE`
3. Append final session entry to `dev-journal/{epic}-{num}.md`

### Step 5.3 — Git branch and commit guidance

Print the git commands (do not run them — the user executes these):

```
## Git Commands for This Story
# Create branch (if not already on it):
git checkout -b feature/{epic-id}-{short-description}

# Stage only the files created for this story:
git add {file1} {file2} ...

# Commit:
git commit -m "Implement {story title} [{story-id}]"

# Note: Never commit directly to main. Never use --no-verify.
```

### Step 5.4 — Announce next story

Print:

```
## Story Complete ✅
US-{epic}-{num} — {title} is done.

Next story: US-{next-epic}-{next-num} — {next title}
To begin: invoke /userstory-development-skill
```

---

## Operational Rules (always active)

1. **Never load `requirements.md` or `project-plan.md` unless explicitly needed** — they are large files. Use `backlog.md` (story-by-story) and `CLAUDE.md` instead.
2. **Never load the entire `backlog.md`** — use grep/search to find only the relevant story block.
3. **One sub-task = one file write pass** — do not batch multiple file creations into a single response without checkpointing between them.
4. **Never skip the code-reviewer or security-reviewer** — both must run after every file write before moving to the next sub-task.
5. **Never assume a prior story's files exist** — always verify with a file existence check before referencing them.
6. **No placeholders or TODO stubs in production code** — if a dependency is missing, raise a blocker (Phase 1.3) rather than writing a stub that will be forgotten.
7. **Always write tests alongside the implementation file** — not after all implementation files are done.
8. **If the user says "continue"** — read `dev-journal/CURRENT.md` first, then resume from "Exact Next Step". Do not ask for context the journal already provides.
9. **If the user specifies a story ID** — check `dev-journal/progress-index.md` to confirm its status before starting. If `COMPLETE`, ask the user if they want to re-open it.
10. **Secrets discipline**: if you ever find yourself about to write a secret value into a file, stop immediately, write `{SECRET_FROM_SECRETS_MANAGER}` as a placeholder, and note it in the journal as an open item.
