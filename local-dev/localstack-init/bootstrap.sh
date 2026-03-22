#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — LocalStack resource provisioning for Containers with Middleware
#
# Creates the AWS resource topology (SNS FIFO, SQS FIFO, DLQ, S3, Secrets
# Manager) matching the production topology for local development and
# integration testing.
#
# Execution:
#   Runs automatically on LocalStack startup via the init scripts mechanism.
#   Mounted to /etc/localstack/init/ready.d/ in docker-compose.yml.
#   LocalStack executes this with bash when it reaches READY state.
#
# Resources created:
#   SNS FIFO  : hermes-flightschedules.fifo
#   SQS FIFO  : hermes-flightschedules-consumer-a.fifo  (redrive → DLQ after 3 receives)
#   SQS DLQ   : hermes-flightschedules-dlq.fifo
#   S3 bucket : hermes-claim-check-local
#   Secrets   : hermes/local/solace-credentials
#               hermes/local/solace-mtls-config
#
# Idempotent: SNS/SQS create operations are naturally idempotent.
#             Secrets are deleted (force) then recreated on each run.
#
# Region    : us-east-1  (matches DEFAULT_REGION in docker-compose.yml)
# Account   : 000000000000  (LocalStack default)
# =============================================================================

set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

# Wrapper to avoid repeating endpoint/region/formatting flags on every call
aws_cmd() {
  aws --endpoint-url "$ENDPOINT" \
      --region "$REGION" \
      --no-cli-pager \
      --output text \
      "$@"
}

echo "==> [bootstrap] LocalStack provisioning started"

# ---------------------------------------------------------------------------
# 1. SNS FIFO topic
#    create-topic is idempotent — returns existing ARN if already present
# ---------------------------------------------------------------------------
echo "==> [1/6] Creating SNS FIFO topic: hermes-flightschedules.fifo"
SNS_TOPIC_ARN=$(aws_cmd sns create-topic \
  --name hermes-flightschedules.fifo \
  --attributes FifoTopic=true,ContentBasedDeduplication=false \
  --query TopicArn)
echo "    ARN: ${SNS_TOPIC_ARN}"

# ---------------------------------------------------------------------------
# 2. SQS DLQ FIFO
#    Created first so its ARN is available for the consumer queue redrive policy
#    create-queue is idempotent — returns existing URL if already present
# ---------------------------------------------------------------------------
echo "==> [2/6] Creating SQS DLQ FIFO: hermes-flightschedules-dlq.fifo"
DLQ_URL=$(aws_cmd sqs create-queue \
  --queue-name hermes-flightschedules-dlq.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=false \
  --query QueueUrl)
DLQ_ARN=$(aws_cmd sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names QueueArn \
  --query Attributes.QueueArn)
echo "    URL: ${DLQ_URL}"
echo "    ARN: ${DLQ_ARN}"

# ---------------------------------------------------------------------------
# 3. SQS FIFO consumer queue
#    Redrive policy: route to DLQ after 3 failed receives
#    create-queue is idempotent
# ---------------------------------------------------------------------------
echo "==> [3/6] Creating SQS FIFO queue: hermes-flightschedules-consumer-a.fifo"
QUEUE_URL=$(aws_cmd sqs create-queue \
  --queue-name hermes-flightschedules-consumer-a.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=false,VisibilityTimeout=30 \
  --query QueueUrl)
QUEUE_ARN=$(aws_cmd sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --query Attributes.QueueArn)
echo "    URL: ${QUEUE_URL}"
echo "    ARN: ${QUEUE_ARN}"

# Set redrive policy separately — avoids bash quoting issues with inline JSON
aws_cmd sqs set-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attributes "RedrivePolicy={\"deadLetterTargetArn\":\"${DLQ_ARN}\",\"maxReceiveCount\":\"3\"}" \
  > /dev/null

# ---------------------------------------------------------------------------
# 4. SNS → SQS subscription with SQS access policy
#    Raw message delivery: SNS passes the payload directly without envelope
# ---------------------------------------------------------------------------
echo "==> [4/6] Subscribing SQS queue to SNS topic (raw message delivery)"
aws_cmd sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol sqs \
  --notification-endpoint "$QUEUE_ARN" \
  --attributes RawMessageDelivery=true \
  > /dev/null

# Grant SNS permission to write to the SQS queue
SQS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowSnsPublish",
    "Effect": "Allow",
    "Principal": {"Service": "sns.amazonaws.com"},
    "Action": "sqs:SendMessage",
    "Resource": "${QUEUE_ARN}",
    "Condition": {"ArnEquals": {"aws:SourceArn": "${SNS_TOPIC_ARN}"}}
  }]
}
EOF
)
aws_cmd sqs set-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attributes "Policy=${SQS_POLICY}" \
  > /dev/null
echo "    Subscription configured"

# ---------------------------------------------------------------------------
# 5. S3 bucket for large message claim-check payloads
#    create-bucket is idempotent in LocalStack
# ---------------------------------------------------------------------------
echo "==> [5/6] Creating S3 bucket: hermes-claim-check-local"
aws_cmd s3api create-bucket \
  --bucket hermes-claim-check-local \
  --region us-east-1 \
  > /dev/null

aws_cmd s3api put-public-access-block \
  --bucket hermes-claim-check-local \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  > /dev/null
echo "    Bucket created with public access blocked"

# ---------------------------------------------------------------------------
# 6. Secrets Manager — test Solace credentials and mTLS cert paths
#
#    ⚠ LOCAL DEV ONLY — these are not real credentials.
#    Values match the local Docker Compose stack defaults from .env.example.
#    In staging/prod, real values are loaded from AWS Secrets Manager via ESO.
#
#    Idempotency: delete (force, no recovery delay) then recreate on each run.
# ---------------------------------------------------------------------------
echo "==> [6/6] Creating Secrets Manager test secrets"

for secret_id in \
  "hermes/local/solace-credentials" \
  "hermes/local/solace-mtls-config"; do
  aws_cmd secretsmanager delete-secret \
    --secret-id "$secret_id" \
    --force-delete-without-recovery \
    > /dev/null 2>&1 || true
done

# Solace connection credentials — matches docker-compose.yml admin user
aws_cmd secretsmanager create-secret \
  --name hermes/local/solace-credentials \
  --description "Local dev Solace connection credentials (not real)" \
  --secret-string '{
    "host":     "tcp://solace:55555",
    "vpn":      "default",
    "username": "admin",
    "password": "admin"
  }' \
  > /dev/null

# mTLS cert paths — cert files are mounted at /mnt/certs in the app container (US-E0-005)
# Keystore/truststore passwords match KEYSTORE_PASSWORD / TRUSTSTORE_PASSWORD in .env.example
aws_cmd secretsmanager create-secret \
  --name hermes/local/solace-mtls-config \
  --description "Local dev mTLS cert paths (not real — points to generate-certs.sh output)" \
  --secret-string '{
    "keystorePath":       "/mnt/certs/client-keystore.p12",
    "keystorePassword":   "changeit",
    "truststorePath":     "/mnt/certs/truststore.jks",
    "truststorePassword": "changeit"
  }' \
  > /dev/null

echo "    Secrets created: hermes/local/solace-credentials, hermes/local/solace-mtls-config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==> [bootstrap] Provisioning complete."
echo ""
printf "%-44s  %s\n" "Resource" "Identifier"
printf "%-44s  %s\n" "--------" "----------"
printf "%-44s  %s\n" "SNS FIFO topic"                   "${SNS_TOPIC_ARN}"
printf "%-44s  %s\n" "SQS consumer queue"               "${QUEUE_URL}"
printf "%-44s  %s\n" "SQS DLQ"                          "${DLQ_URL}"
printf "%-44s  %s\n" "S3 claim-check bucket"            "hermes-claim-check-local"
printf "%-44s  %s\n" "Solace credentials secret"        "hermes/local/solace-credentials"
printf "%-44s  %s\n" "mTLS config secret"               "hermes/local/solace-mtls-config"
