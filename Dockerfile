# =============================================================================
# Dockerfile — Hermes multi-stage build
#
# Stage 1 (builder): Maven on Eclipse Temurin 17 JDK — compiles and packages
# Stage 2 (runtime): Red Hat UBI 9 + Eclipse Temurin 17 JRE — minimal runtime
#
# Build:
#   docker build -t hermes:local .
#
# Run (local dev — use docker compose instead):
#   docker run --env-file local-dev/.env hermes:local
#
# Security notes:
#   - Runtime image runs as non-root UID 1001
#   - No build tools, Maven cache, or source code in the final image
#   - Base image pulled fresh on every CI build — do not pin to a stale digest
#   - Production ECR push uses a SHA-pinned digest (set by buildspec-docker.yml)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1 — Build
# Eclipse Temurin 17 JDK on Ubuntu (official Maven image).
# Only the compiled JAR is carried forward to the runtime stage.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:17-jdk AS builder

WORKDIR /build

# Copy dependency manifests first to exploit Docker layer caching.
# Dependencies are re-downloaded only when pom.xml changes, not on every source change.
COPY pom.xml ./
COPY .mvn/ .mvn/
COPY mvnw ./
RUN chmod +x mvnw

# Download dependencies (offline after this layer is cached).
# -B  : batch mode (no interactive prompts)
# -q  : quiet output (reduce CI log noise)
# --no-transfer-progress suppresses download progress bars in CI
RUN ./mvnw -B -q dependency:go-offline --no-transfer-progress

# Copy source after dependency layer — maximises cache hit rate.
COPY src/ src/

# Build the fat JAR, skipping tests (tests run in a separate CI stage).
# -Dmaven.test.skip=true skips both compilation and execution of tests.
RUN ./mvnw -B -q package -Dmaven.test.skip=true --no-transfer-progress

# -----------------------------------------------------------------------------
# Stage 2 — Runtime
# Eclipse Temurin 17 JRE on Red Hat UBI 9 Minimal (eclipse-temurin:17-jre-ubi9-minimal).
# Satisfies CLAUDE.md: "Red Hat UBI 9 + Eclipse Temurin JRE 17".
# UBI 9 is the approved base for ROSA (OpenShift 4.18+) workloads.
# Pull latest quarterly patch on every build — do not pin to a stale digest here;
# the CI buildspec-docker.yml pins the final ECR push to a SHA for reproducibility.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:17-jre-ubi9-minimal AS runtime

# Install shadow-utils to enable groupadd/useradd on ubi9-minimal.
RUN microdnf install -y shadow-utils \
    && microdnf clean all \
    && rm -rf /var/cache/dnf

# Create a non-root system user and group.
# UID/GID 1001 — non-zero, not root, consistent with OpenShift SCC requirements.
RUN groupadd --system --gid 1001 hermes \
    && useradd --system --uid 1001 --gid hermes --no-create-home --shell /sbin/nologin hermes

WORKDIR /app

# Copy the fat JAR from the builder stage.
COPY --from=builder --chown=hermes:hermes /build/target/hermes-*.jar app.jar

# Drop privileges — run as non-root hermes user.
USER hermes

# Expose the application port only. The management port (8081) is not exposed
# externally; it is accessed internally by Kubernetes probes via the pod IP.
EXPOSE 8080

# JVM tuning:
#   -XX:+UseContainerSupport          — respect cgroup CPU/memory limits (default in JDK 17)
#   -XX:MaxRAMPercentage=75.0         — use 75% of container memory for heap
#   -XX:+ExitOnOutOfMemoryError       — crash fast on OOM rather than thrashing
#   -Djava.security.egd=...           — faster SecureRandom seeding in containers
#   -Dspring.profiles.active          — overridden at runtime by K8s env var
ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-XX:+ExitOnOutOfMemoryError", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-jar", "app.jar"]
