#!/usr/bin/env bash
# =============================================================================
# generate-certs.sh — Self-signed mTLS certificate generation for local Solace
#
# Generates all certificate artefacts required for local mTLS testing:
#   ca.crt              Self-signed CA certificate
#   server.crt          Server certificate signed by CA (used by Solace)
#   server-combined.pem Server cert + key combined — loaded by Solace container
#   client.crt          Client certificate signed by CA (used by JCSMP)
#   client-keystore.p12 PKCS12 keystore with client cert + key (JCSMP keystore)
#   truststore.jks      JKS truststore containing CA cert (JCSMP truststore)
#
# Usage (run from any directory):
#   ./local-dev/certs/generate-certs.sh
#
# Passwords are read from local-dev/.env if present.
# Required keys:
#   KEYSTORE_PASSWORD   — password for client-keystore.p12  (default: changeit)
#   TRUSTSTORE_PASSWORD — password for truststore.jks       (default: changeit)
#
# Idempotent: removes and regenerates all output files on every run.
# Requires: openssl, keytool (provided by any JDK)
# Platform: run inside Git Bash, WSL, or macOS/Linux terminal
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
OUT="$SCRIPT_DIR"

CERT_VALIDITY_DAYS=825   # <= 825 required by modern TLS clients (Apple, Chrome)
CA_VALIDITY_DAYS=3650    # 10 years for the local-only CA

# ---------------------------------------------------------------------------
# Load passwords from .env via grep/sed — does not source arbitrary shell code
# ---------------------------------------------------------------------------
KEYSTORE_PASSWORD="changeit"
TRUSTSTORE_PASSWORD="changeit"

if [[ -f "$ENV_FILE" ]]; then
  _ks=$(grep -E '^KEYSTORE_PASSWORD=' "$ENV_FILE" 2>/dev/null | head -1 \
        | sed 's/^KEYSTORE_PASSWORD=//' | tr -d '"'"'" | tr -d '\r' || true)
  _ts=$(grep -E '^TRUSTSTORE_PASSWORD=' "$ENV_FILE" 2>/dev/null | head -1 \
        | sed 's/^TRUSTSTORE_PASSWORD=//' | tr -d '"'"'" | tr -d '\r' || true)
  [[ -n "$_ks" ]] && KEYSTORE_PASSWORD="$_ks"
  [[ -n "$_ts" ]] && TRUSTSTORE_PASSWORD="$_ts"
fi

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
for cmd in openssl keytool; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not on PATH." >&2
    case "$cmd" in
      openssl)  echo "  Install: brew install openssl  OR  apt-get install openssl" >&2 ;;
      keytool)  echo "  Install a JDK (keytool is bundled with Eclipse Temurin 17)" >&2 ;;
    esac
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Idempotent cleanup — remove all previously generated certificate files
# ---------------------------------------------------------------------------
echo "==> Cleaning previously generated certificate files"
rm -f \
  "$OUT/ca.key"        "$OUT/ca.crt"         "$OUT/ca.srl" \
  "$OUT/server.key"    "$OUT/server.csr"      "$OUT/server.crt" \
  "$OUT/server-combined.pem" "$OUT/server-ext.cnf" \
  "$OUT/client.key"    "$OUT/client.csr"      "$OUT/client.crt" \
  "$OUT/client-keystore.p12" "$OUT/truststore.jks"

# ---------------------------------------------------------------------------
# 1. Root CA (local only — 4096-bit RSA, 10-year validity)
# ---------------------------------------------------------------------------
echo "==> [1/5] Generating root CA"
openssl genrsa -out "$OUT/ca.key" 4096 2>/dev/null
openssl req -new -x509 \
  -days "$CA_VALIDITY_DAYS" \
  -key  "$OUT/ca.key" \
  -out  "$OUT/ca.crt" \
  -subj "/CN=Hermes Local CA/O=Hermes Local Dev/C=US"

# ---------------------------------------------------------------------------
# 2. Server certificate for Solace container
#    SAN covers 'solace' (Docker DNS) and 'localhost' (direct connections)
# ---------------------------------------------------------------------------
echo "==> [2/5] Generating server certificate (Solace)"
openssl genrsa -out "$OUT/server.key" 2048 2>/dev/null

openssl req -new \
  -key  "$OUT/server.key" \
  -out  "$OUT/server.csr" \
  -subj "/CN=solace/O=Hermes Local Dev/C=US"

# Write SANs to a temporary config (required by openssl x509 -extfile)
cat > "$OUT/server-ext.cnf" <<EOF
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = solace
DNS.2 = localhost
IP.1  = 127.0.0.1
EOF

openssl x509 -req \
  -days  "$CERT_VALIDITY_DAYS" \
  -in    "$OUT/server.csr" \
  -CA    "$OUT/ca.crt" \
  -CAkey "$OUT/ca.key" \
  -CAcreateserial \
  -out   "$OUT/server.crt" \
  -extfile "$OUT/server-ext.cnf" \
  -extensions v3_req 2>/dev/null

# Combined PEM: certificate then private key — format expected by Solace Standard
cat "$OUT/server.crt" "$OUT/server.key" > "$OUT/server-combined.pem"

# ---------------------------------------------------------------------------
# 3. Client certificate (used by JCSMP / Spring Boot application)
# ---------------------------------------------------------------------------
echo "==> [3/5] Generating client certificate (JCSMP)"
openssl genrsa -out "$OUT/client.key" 2048 2>/dev/null

openssl req -new \
  -key  "$OUT/client.key" \
  -out  "$OUT/client.csr" \
  -subj "/CN=hermes-client/O=Hermes Local Dev/C=US"

openssl x509 -req \
  -days  "$CERT_VALIDITY_DAYS" \
  -in    "$OUT/client.csr" \
  -CA    "$OUT/ca.crt" \
  -CAkey "$OUT/ca.key" \
  -CAcreateserial \
  -out   "$OUT/client.crt" 2>/dev/null

# ---------------------------------------------------------------------------
# 4. PKCS12 client keystore — client cert + key, CA cert as chain entry
#    Alias 'hermes-client' is referenced in application-local.yml (US-E0-005)
# ---------------------------------------------------------------------------
echo "==> [4/5] Creating PKCS12 client keystore: client-keystore.p12"
openssl pkcs12 -export \
  -in       "$OUT/client.crt" \
  -inkey    "$OUT/client.key" \
  -certfile "$OUT/ca.crt" \
  -out      "$OUT/client-keystore.p12" \
  -passout  "pass:${KEYSTORE_PASSWORD}" \
  -name     hermes-client

# ---------------------------------------------------------------------------
# 5. JKS truststore — contains the CA cert only, used to validate the server
# ---------------------------------------------------------------------------
echo "==> [5/5] Creating JKS truststore: truststore.jks"
keytool -importcert \
  -trustcacerts \
  -noprompt \
  -alias    hermes-local-ca \
  -file     "$OUT/ca.crt" \
  -keystore "$OUT/truststore.jks" \
  -storepass "${TRUSTSTORE_PASSWORD}" \
  -storetype JKS

# ---------------------------------------------------------------------------
# File permissions — private keys and keystores restricted to owner only
# ---------------------------------------------------------------------------
chmod 600 \
  "$OUT/ca.key" \
  "$OUT/server.key" \
  "$OUT/client.key" \
  "$OUT/client-keystore.p12" \
  "$OUT/server-combined.pem"

chmod 644 \
  "$OUT/ca.crt" \
  "$OUT/server.crt" \
  "$OUT/client.crt" \
  "$OUT/truststore.jks"

# Remove intermediate working files not needed at runtime
rm -f "$OUT/server.csr" "$OUT/client.csr" "$OUT/server-ext.cnf"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Certificate generation complete."
echo ""
printf "%-30s  %s\n" "File" "Purpose"
printf "%-30s  %s\n" "----" "-------"
printf "%-30s  %s\n" "ca.crt"              "CA certificate"
printf "%-30s  %s\n" "server.crt"          "Solace server certificate"
printf "%-30s  %s\n" "server-combined.pem" "Loaded by Solace container (cert+key)"
printf "%-30s  %s\n" "client.crt"          "Client certificate"
printf "%-30s  %s\n" "client-keystore.p12" "JCSMP keystore  (password: set via KEYSTORE_PASSWORD in .env)"
printf "%-30s  %s\n" "truststore.jks"      "JCSMP truststore (password: set via TRUSTSTORE_PASSWORD in .env)"
echo ""
echo "Next steps:"
echo "  1. Verify KEYSTORE_PASSWORD / TRUSTSTORE_PASSWORD are set in local-dev/.env"
echo "  2. (Re)start Solace: docker compose up -d solace"
echo "     (server-combined.pem is mounted into the container via docker-compose.yml)"
echo "  3. Verify Solace is healthy: docker compose ps"
echo "  4. Configure Solace TLS listener: ./local-dev/solace-init/provision-queues.sh"
