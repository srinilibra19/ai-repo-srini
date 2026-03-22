#!/usr/bin/env bash
# =============================================================================
# setup.sh — Hermes local development stack — one-command setup (Linux/macOS)
#
# Automates: prerequisite checks, .env creation, mTLS cert generation,
# Docker Compose up, health polling, and full infrastructure verification.
#
# Usage:
#   ./local-dev/setup.sh                  # full setup
#   ./local-dev/setup.sh --skip-certs     # skip cert generation (use existing)
#   ./local-dev/setup.sh --skip-verify    # skip post-startup verification
#
# Exit codes:
#   0 — stack started and all verification checks passed
#   1 — setup failed (error printed above)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()    { printf "${GREEN}  ==>${NC} %s\n" "$1"; }
warn()    { printf "${YELLOW}  [!]${NC} %s\n" "$1"; }
error()   { printf "${RED}  [✗]${NC} %s\n" "$1"; }
section() { printf "\n${BOLD}━━━ %s${NC}\n" "$1"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SKIP_CERTS=false
SKIP_VERIFY=false

for arg in "$@"; do
  case "$arg" in
    --skip-certs)  SKIP_CERTS=true ;;
    --skip-verify) SKIP_VERIFY=true ;;
    *)
      printf "Unknown option: %s\n" "$arg"
      printf "Usage: setup.sh [--skip-certs] [--skip-verify]\n"
      exit 1
      ;;
  esac
done

# ===========================================================================
# 1 — Prerequisite checks
# ===========================================================================
section "1. Prerequisite checks"

PREREQ_FAIL=false

# Docker engine
if ! command -v docker &>/dev/null; then
  error "Docker not found — install Docker Desktop: https://www.docker.com/products/docker-desktop"
  PREREQ_FAIL=true
elif ! docker info &>/dev/null; then
  error "Docker daemon is not running — start Docker Desktop and try again"
  PREREQ_FAIL=true
else
  DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
  info "Docker $DOCKER_VER — running"
fi

# Docker Compose v2
if ! docker compose version &>/dev/null; then
  error "Docker Compose v2 not found — update Docker Desktop to 4.x+"
  PREREQ_FAIL=true
else
  COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "unknown")
  info "Docker Compose $COMPOSE_VER"
fi

# AWS CLI — optional but warn clearly if absent
if ! command -v aws &>/dev/null; then
  warn "AWS CLI not found — LocalStack verification will be skipped"
  warn "  Install: brew install awscli   OR   winget install Amazon.AWSCLI"
else
  AWS_VER=$(aws --version 2>&1 | awk '{print $1}' || echo "unknown")
  info "AWS CLI — $AWS_VER"
fi

if [ "$PREREQ_FAIL" = true ]; then
  printf "\n${RED}${BOLD}Prerequisite checks failed. Fix the errors above and re-run.${NC}\n\n"
  exit 1
fi

# ===========================================================================
# 2 — Environment file
# ===========================================================================
section "2. Environment file"

ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

if [ -f "$ENV_FILE" ]; then
  info ".env already exists — using existing file"
else
  if [ ! -f "$ENV_EXAMPLE" ]; then
    error ".env.example not found at $ENV_EXAMPLE"
    exit 1
  fi
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  info "Created .env from .env.example"
  warn "Review $ENV_FILE and adjust any values if needed"
fi

# ===========================================================================
# 3 — mTLS certificates
# ===========================================================================
section "3. mTLS certificates"

CERT_SCRIPT="$SCRIPT_DIR/certs/generate-certs.sh"
CERT_MARKER="$SCRIPT_DIR/certs/server-combined.pem"

if [ "$SKIP_CERTS" = true ]; then
  warn "--skip-certs set — skipping certificate generation"
elif [ -f "$CERT_MARKER" ]; then
  info "Certificates already exist — skipping generation"
  info "  To regenerate: rm local-dev/certs/*.pem && ./local-dev/setup.sh"
else
  if [ ! -f "$CERT_SCRIPT" ]; then
    error "generate-certs.sh not found at $CERT_SCRIPT"
    exit 1
  fi
  info "Generating mTLS certificates..."
  bash "$CERT_SCRIPT"
  info "Certificates generated"
fi

# ===========================================================================
# 4 — Docker Compose up
# ===========================================================================
section "4. Starting Docker Compose stack"

cd "$SCRIPT_DIR"
info "Running: docker compose up -d"
docker compose up -d

# ===========================================================================
# 5 — Wait for services to become healthy
# ===========================================================================
section "5. Waiting for services to become healthy"

POLL_TIMEOUT=120
POLL_INTERVAL=10
ELAPSED=0
SERVICES=(hermes-solace hermes-postgres hermes-localstack)

info "Polling every ${POLL_INTERVAL}s (timeout: ${POLL_TIMEOUT}s)"

while true; do
  ALL_HEALTHY=true
  STATUS_LINE=""

  for svc in "${SERVICES[@]}"; do
    h=$(docker inspect --format='{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "missing")
    STATUS_LINE="$STATUS_LINE $svc=$h"
    [ "$h" != "healthy" ] && ALL_HEALTHY=false
  done

  printf "  [%3ds]%s\n" "$ELAPSED" "$STATUS_LINE"

  if [ "$ALL_HEALTHY" = true ]; then
    info "All services healthy after ${ELAPSED}s"
    break
  fi

  if [ "$ELAPSED" -ge "$POLL_TIMEOUT" ]; then
    error "Timed out after ${POLL_TIMEOUT}s waiting for healthy status"
    error "Run 'docker compose logs' to investigate"
    exit 1
  fi

  sleep "$POLL_INTERVAL"
  ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
done

# Give hermes-solace-init time to complete after Solace becomes healthy
info "Waiting 10s for hermes-solace-init to complete provisioning..."
sleep 10

# ===========================================================================
# 6 — Infrastructure verification
# ===========================================================================
section "6. Infrastructure verification"

if [ "$SKIP_VERIFY" = true ]; then
  warn "--skip-verify set — skipping verification"
  warn "  Run './local-dev/verify.sh' manually when ready"
else
  VERIFY_SCRIPT="$SCRIPT_DIR/verify.sh"
  if [ ! -f "$VERIFY_SCRIPT" ]; then
    error "verify.sh not found at $VERIFY_SCRIPT"
    exit 1
  fi
  bash "$VERIFY_SCRIPT"
fi

# ===========================================================================
# Done
# ===========================================================================
printf "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${GREEN}${BOLD} Local stack is up and verified. You are ready to develop!${NC}\n"
printf "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "\n"
printf "  Solace Admin UI : http://localhost:8080  (admin / admin)\n"
printf "  PostgreSQL      : localhost:5432  db=hermes  user=hermes\n"
printf "  LocalStack      : http://localhost:4566\n"
printf "\n"
printf "  Next step: run the application\n"
printf "    ./mvnw spring-boot:run -Dspring-boot.run.profiles=local\n"
printf "\n"
