#!/bin/sh
# =============================================================================
# provision-queues.sh — Solace PubSub+ local queue and subscription provisioning
#
# Uses the SEMPv2 REST Management API to create the queue topology required for
# local development and integration testing of the hermes consumer application.
#
# Resources created (all in the 'default' Message VPN):
#   Queue       : hermes.flightschedules       (non-exclusive, 4 GB spool)
#   Subscription: flightschedules/>            (wildcard — matches all flight events)
#   DMQ         : hermes.flightschedules.dmq   (dead message queue, 1 GB spool)
#
# Execution:
#   Runs automatically via the hermes-solace-init service in docker-compose.yml.
#   That service depends_on: solace (service_healthy), so Solace is ready when
#   this script starts.
#
# Idempotent:
#   All SEMPv2 create calls return HTTP 200 (OK) if the resource already exists
#   with the same name. The script treats both 200 and 200-range as success.
#
# Usage (manual):
#   docker compose run --rm hermes-solace-init
#
# Platform: POSIX sh — runs inside curlimages/curl:8 Linux container.
# =============================================================================

set -eu

SEMP_BASE="http://solace:8080/SEMP/v2/config/msgVpns/default"
SEMP_AUTH="admin:admin"
CONTENT_TYPE="Content-Type: application/json"

# ---------------------------------------------------------------------------
# Helper: POST to SEMPv2 and check for success
# Exits with code 1 if the HTTP response code is not 2xx or 4xx (conflict=ok)
# ---------------------------------------------------------------------------
semp_post() {
  url="$1"
  body="$2"
  description="$3"

  http_code=$(curl \
    --silent \
    --write-out "%{http_code}" \
    --output /tmp/semp_response.json \
    --user "$SEMP_AUTH" \
    --header "$CONTENT_TYPE" \
    --request POST \
    --data "$body" \
    "$url")

  # SEMPv2 returns 200 for success and 400 for "already exists" (idempotent)
  case "$http_code" in
    200|201) echo "    [OK ${http_code}] ${description}" ;;
    400)
      if grep -q '"ALREADY_EXISTS"' /tmp/semp_response.json; then
        echo "    [SKIP 400] ${description} — already exists"
      else
        echo "    [FAIL ${http_code}] ${description}"
        cat /tmp/semp_response.json
        exit 1
      fi
      ;;
    *)
      echo "    [FAIL ${http_code}] ${description}"
      cat /tmp/semp_response.json
      exit 1
      ;;
  esac
}

echo "==> [provision-queues] Solace SEMPv2 provisioning started"
echo "    Target: ${SEMP_BASE}"

# ---------------------------------------------------------------------------
# 1. Dead Message Queue — hermes.flightschedules.dmq
#    Created first so the main queue can reference it via deadMsgQueue attribute
# ---------------------------------------------------------------------------
echo "==> [1/3] Creating DMQ: hermes.flightschedules.dmq"
semp_post \
  "${SEMP_BASE}/queues" \
  '{
    "queueName":      "hermes.flightschedules.dmq",
    "accessType":     "non-exclusive",
    "egressEnabled":  true,
    "ingressEnabled": true,
    "maxMsgSpoolUsage": 1024,
    "permission":     "consume",
    "respectMsgPriorityEnabled": false
  }' \
  "DMQ hermes.flightschedules.dmq"

# ---------------------------------------------------------------------------
# 2. Main consumer queue — hermes.flightschedules
#    Non-exclusive: multiple consumers can compete for messages (KEDA scale-out)
#    4 GB spool (4096 MB) — matches production sizing for local validation
#    deadMsgQueue: routes undeliverable messages to the DMQ above
# ---------------------------------------------------------------------------
echo "==> [2/3] Creating queue: hermes.flightschedules"
semp_post \
  "${SEMP_BASE}/queues" \
  '{
    "queueName":        "hermes.flightschedules",
    "accessType":       "non-exclusive",
    "egressEnabled":    true,
    "ingressEnabled":   true,
    "maxMsgSpoolUsage": 4096,
    "permission":       "consume",
    "deadMsgQueue":     "hermes.flightschedules.dmq",
    "maxDeliveredUnackedMsgsPerFlow": 32,
    "respectMsgPriorityEnabled": false
  }' \
  "Queue hermes.flightschedules"

# ---------------------------------------------------------------------------
# 3. Topic subscription — flightschedules/>
#    Wildcard subscribes to all topics under flightschedules/ hierarchy.
#    Publishers send to: flightschedules/events, flightschedules/updates, etc.
# ---------------------------------------------------------------------------
echo "==> [3/3] Adding topic subscription: flightschedules/>"
semp_post \
  "${SEMP_BASE}/queues/hermes.flightschedules/subscriptions" \
  '{
    "subscriptionTopic": "flightschedules/>"
  }' \
  "Subscription flightschedules/> on hermes.flightschedules"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> [provision-queues] Provisioning complete."
echo ""
printf "%-40s  %s\n" "Resource" "Details"
printf "%-40s  %s\n" "--------" "-------"
printf "%-40s  %s\n" "Queue hermes.flightschedules"     "non-exclusive, 4 GB spool, DMQ linked"
printf "%-40s  %s\n" "Subscription flightschedules/>"   "on hermes.flightschedules"
printf "%-40s  %s\n" "DMQ hermes.flightschedules.dmq"   "non-exclusive, 1 GB spool"
echo ""
echo "Verify via Solace admin UI: http://localhost:8080 (admin / admin)"
echo "  Messaging -> Queues -> hermes.flightschedules"
