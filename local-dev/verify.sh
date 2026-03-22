#!/usr/bin/env bash
# =============================================================================
# verify.sh — Hermes local infrastructure verification
#
# Checks that all Docker Compose services are healthy and all provisioned
# resources (Solace queues, LocalStack SNS/SQS/S3, PostgreSQL) are present.
#
# Usage (standalone):
#   ./local-dev/verify.sh
#
# Usage (with SDKPerf publish test):
#   SDKPERF_HOME=/path/to/sdkperf ./local-dev/verify.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

_pass_count=0
_fail_count=0

_ok()      { printf "  ${GREEN}[PASS]${NC} %s\n" "$1"; _pass_count=$(( _pass_count + 1 )); }
_fail_msg(){ printf "  ${RED}[FAIL]${NC} %s\n" "$1"; _fail_count=$(( _fail_count + 1 )); }
_skip()    { printf "  ${YELLOW}[SKIP]${NC} %s\n" "$1"; }
_hdr()     { printf "\n${BOLD}── %s${NC}\n" "$1"; }

# ---------------------------------------------------------------------------
# LocalStack AWS CLI environment (dummy credentials — LocalStack does not validate)
# ---------------------------------------------------------------------------
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LS_ENDPOINT="http://localhost:4566"

# ---------------------------------------------------------------------------
# Helper: inspect container attributes
# ---------------------------------------------------------------------------
_container_health() {
  docker inspect --format='{{.State.Health.Status}}' "$1" 2>/dev/null || echo "missing"
}
_container_state() {
  docker inspect --format='{{.State.Status}}' "$1" 2>/dev/null || echo "missing"
}
_container_exit() {
  docker inspect --format='{{.State.ExitCode}}' "$1" 2>/dev/null || echo "missing"
}

# ===========================================================================
# 1 — Container health
# ===========================================================================
_hdr "1. Container health"

for svc in hermes-solace hermes-postgres hermes-localstack; do
  h=$(_container_health "$svc")
  if [ "$h" = "healthy" ]; then
    _ok "$svc → healthy"
  else
    _fail_msg "$svc → $h  (expected: healthy)"
  fi
done

# hermes-solace-init is a one-shot container — expect exited with code 0
init_state=$(_container_state "hermes-solace-init")
init_exit=$(_container_exit  "hermes-solace-init")

if [ "$init_state" = "exited" ] && [ "$init_exit" = "0" ]; then
  _ok "hermes-solace-init → exited(0)  provisioning complete"
elif [ "$init_state" = "missing" ]; then
  _fail_msg "hermes-solace-init → container not found  (run: docker compose up -d)"
else
  _fail_msg "hermes-solace-init → state=$init_state exit=$init_exit  (expected: exited/0)"
fi

# ===========================================================================
# 2 — Solace queue provisioning
# ===========================================================================
_hdr "2. Solace queue provisioning"

init_logs=$(docker logs hermes-solace-init 2>/dev/null || echo "")

if echo "$init_logs" | grep -q "Provisioning complete"; then
  _ok "provision-queues.sh completed successfully"
else
  _fail_msg "provision-queues.sh did not complete  (check: docker logs hermes-solace-init)"
fi

# Check DMQ — unique suffix .dmq avoids overlap with main queue name
if echo "$init_logs" | grep -q "hermes\.flightschedules\.dmq"; then
  _ok "hermes.flightschedules.dmq"
else
  _fail_msg "hermes.flightschedules.dmq  not found in provisioning log"
fi

# Check main queue — match lines containing "Queue hermes.flightschedules" to avoid
# matching the DMQ line (which also contains "hermes.flightschedules" as a substring)
if echo "$init_logs" | grep -qE "Queue hermes\.flightschedules[^.]"; then
  _ok "hermes.flightschedules"
else
  _fail_msg "hermes.flightschedules  not found in provisioning log"
fi

# Check topic subscription
if echo "$init_logs" | grep -q "flightschedules/>"; then
  _ok "flightschedules/>  subscription"
else
  _fail_msg "flightschedules/>  subscription not found in provisioning log"
fi

# ===========================================================================
# 3 — LocalStack AWS resources
# ===========================================================================
_hdr "3. LocalStack AWS resources"

if ! command -v aws &>/dev/null; then
  _skip "AWS CLI not installed — skipping LocalStack checks"
  _skip "  Install: winget install Amazon.AWSCLI   OR   brew install awscli"
else
  sns_out=$(aws --endpoint-url="$LS_ENDPOINT" sns list-topics --output text 2>/dev/null || echo "")
  sqs_out=$(aws --endpoint-url="$LS_ENDPOINT" sqs list-queues  --output text 2>/dev/null || echo "")
  s3_out=$( aws --endpoint-url="$LS_ENDPOINT" s3  ls           2>/dev/null || echo "")

  if echo "$sns_out" | grep -q "hermes-flightschedules.fifo"; then
    _ok "SNS FIFO topic : hermes-flightschedules.fifo"
  else
    _fail_msg "SNS FIFO topic : hermes-flightschedules.fifo  not found"
  fi

  if echo "$sqs_out" | grep -q "hermes-flightschedules-consumer-a.fifo"; then
    _ok "SQS FIFO queue : hermes-flightschedules-consumer-a.fifo"
  else
    _fail_msg "SQS FIFO queue : hermes-flightschedules-consumer-a.fifo  not found"
  fi

  if echo "$sqs_out" | grep -q "hermes-flightschedules-dlq.fifo"; then
    _ok "SQS DLQ        : hermes-flightschedules-dlq.fifo"
  else
    _fail_msg "SQS DLQ        : hermes-flightschedules-dlq.fifo  not found"
  fi

  if echo "$s3_out" | grep -q "hermes-claim-check-local"; then
    _ok "S3 bucket      : hermes-claim-check-local"
  else
    _fail_msg "S3 bucket      : hermes-claim-check-local  not found"
  fi
fi

# ===========================================================================
# 4 — PostgreSQL
# ===========================================================================
_hdr "4. PostgreSQL"

if docker compose -f "$SCRIPT_DIR/docker-compose.yml" exec -T postgres \
    pg_isready -U hermes -d hermes >/dev/null 2>&1; then
  _ok "PostgreSQL accepting connections  localhost:5432  db=hermes"
else
  _fail_msg "PostgreSQL not ready  (container: hermes-postgres)"
fi

# ===========================================================================
# 5 — SDKPerf test publish (optional)
# ===========================================================================
_hdr "5. SDKPerf test publish (optional)"

SDKPERF_HOME="${SDKPERF_HOME:-}"

if [ -z "$SDKPERF_HOME" ]; then
  _skip "SDKPERF_HOME not set — skipping publish test"
  _skip "  To enable: SDKPERF_HOME=/path/to/sdkperf ./local-dev/verify.sh"
else
  SDKPERF_BIN="$SDKPERF_HOME/sdkperf_java"
  [ ! -f "$SDKPERF_BIN" ] && SDKPERF_BIN="$SDKPERF_HOME/sdkperf_java.sh"

  if [ ! -f "$SDKPERF_BIN" ]; then
    _skip "sdkperf_java not found in SDKPERF_HOME=$SDKPERF_HOME"
  else
    if "$SDKPERF_BIN" \
        -cip=tcp://localhost:55555 \
        -cu=admin@default \
        -cp=admin \
        -pql=flightschedules/events \
        -mn=3 -mr=1 -msa=512 \
        -q >/dev/null 2>&1; then
      _ok "SDKPerf published 3 test messages → flightschedules/events"
    else
      _fail_msg "SDKPerf publish failed  (is Solace healthy? is port 55555 reachable?)"
    fi
  fi
fi

# ===========================================================================
# Summary
# ===========================================================================
printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD} Verification Summary${NC}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "  ${GREEN}PASS : %d${NC}\n" "$_pass_count"
printf "  ${RED}FAIL : %d${NC}\n"  "$_fail_count"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

if [ "$_fail_count" -eq 0 ]; then
  printf "\n  ${GREEN}${BOLD}All checks passed — local stack is ready.${NC}\n\n"
  exit 0
else
  printf "\n  ${RED}${BOLD}%d check(s) failed — review output above.${NC}\n\n" "$_fail_count"
  exit 1
fi
