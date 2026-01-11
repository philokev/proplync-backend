# Multi-stage build for PropLync.ai Quarkus backend
# Compatible with Podman and OpenShift
# Build locally first: mvn clean package -DskipTests

# Stage 1: Build (optional - can be done locally)
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

# Maven is already installed in this image

# Copy Maven files
COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline -B || true

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests -B

# Stage 2: Production
FROM registry.access.redhat.com/ubi9/openjdk-17-runtime:latest

WORKDIR /app

USER root
RUN chown -R 1001:0 /app && chmod -R 775 /app

# Copy the built application from builder (or from local build)
COPY --from=builder --chown=1001:0 /app/target/quarkus-app /app

# Alternative: If building locally, uncomment this and comment the COPY above:
# COPY --chown=1001:0 target/quarkus-app /app

USER 1001

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/q/health || exit 1

# Run Quarkus
CMD ["java", "-jar", "/app/quarkus-run.jar"]
