#!/usr/bin/env bash

# ======================================================================
# Traefik & Certs Dumper Deployment Script
# ======================================================================
# Uses a unified .env file for both Traefik and certs-dumper configuration.
# Computes host ports, ensures necessary files/directories, and starts both containers.

# Ensure script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Path to the unified environment file
ENV_FILE="/home/administrator/projects/secrets/traefik.env"

# --- Pre-flight Checks ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Environment file not found at $ENV_FILE"
  exit 1
fi

# Source all variables from the environment file
set -o allexport
source "$ENV_FILE"
set +o allexport

# --- Variable Validation ---
# Validate Traefik variables
: "${TRAEFIK_CONTAINER_NAME:?TRAEFIK_CONTAINER_NAME must be set}"
: "${TRAEFIK_IMAGE:?TRAEFIK_IMAGE must be set}"
: "${TRAEFIK_NETWORK:?TRAEFIK_NETWORK must be set}"
: "${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS:?TRAEFIK_ENTRYPOINTS_WEB_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS:?TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS must be set}"

# Validate Certs Dumper variables
: "${CERTS_DUMPER_CONTAINER_NAME:?CERTS_DUMPER_CONTAINER_NAME must be set}"
: "${CERTS_DUMPER_IMAGE:?CERTS_DUMPER_IMAGE must be set}"
: "${TRAEFIK_ACME_FILE_PATH:?TRAEFIK_ACME_FILE_PATH must be set}"
: "${TRAEFIK_CERTS_DUMP_PATH:?TRAEFIK_CERTS_DUMP_PATH must be set}"

# --- Docker & File System Preparation ---

# Create Docker network if it doesn't exist
echo "Ensuring Docker network '$TRAEFIK_NETWORK' exists..."
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || true

# Prepare acme.json file for Let's Encrypt storage
echo "Preparing acme.json file at $TRAEFIK_ACME_FILE_PATH..."
touch "$TRAEFIK_ACME_FILE_PATH" && chmod 600 "$TRAEFIK_ACME_FILE_PATH"

# Prepare the directory for dumped certificates
echo "Preparing certificate dump directory at $TRAEFIK_CERTS_DUMP_PATH..."
mkdir -p "$TRAEFIK_CERTS_DUMP_PATH"

# --- Deploy Traefik Container ---

# Compute host ports from entryPoint addresses
HTTP_PORT="${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS#:}"
HTTPS_PORT="${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS#:}"

echo "Deploying Traefik container '$TRAEFIK_CONTAINER_NAME'..."
# Remove existing container if present
docker rm -f "$TRAEFIK_CONTAINER_NAME" 2>/dev/null || true
# Pull the latest image
docker pull "$TRAEFIK_IMAGE"
# Run the container
docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart=always \
  --network="$TRAEFIK_NETWORK" \
  --env-file="$ENV_FILE" \
  -p "${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS#:}:80" \
  -p "${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS#:}:443" \
  -p "${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS#:}:8083" \
  -p "${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS#:}:9100" \
  -p "${TRAEFIK_ENTRYPOINTS_SMTP_ADDRESS#:}:25" \
  -p "${TRAEFIK_ENTRYPOINTS_SMTPS_ADDRESS#:}:465" \
  -p "${TRAEFIK_ENTRYPOINTS_SUBMISSION_ADDRESS#:}:587" \
  -p "${TRAEFIK_ENTRYPOINTS_IMAPS_ADDRESS#:}:993" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$TRAEFIK_ACME_FILE_PATH":/etc/traefik/acme.json:rw \
  -v "$SCRIPT_DIR/traefik.yml":/etc/traefik/traefik.yml:ro \
  -v "$SCRIPT_DIR/redirect.yml":/etc/traefik/redirect.yml:ro \
  "$TRAEFIK_IMAGE"

# --- Deploy Traefik Certs Dumper Container ---

echo "Deploying Traefik Certs Dumper container '$CERTS_DUMPER_CONTAINER_NAME'..."
# Remove existing container if present
docker rm -f "$CERTS_DUMPER_CONTAINER_NAME" 2>/dev/null || true
# Pull the latest image
docker pull "$CERTS_DUMPER_IMAGE"
# Run the container
docker run -d \
  --name "$CERTS_DUMPER_CONTAINER_NAME" \
  --restart=always \
  --network="$TRAEFIK_NETWORK" \
  -v "$TRAEFIK_ACME_FILE_PATH":/traefik/acme.json:ro \
  -v "$TRAEFIK_CERTS_DUMP_PATH":/certs \
  "$CERTS_DUMPER_IMAGE" \
  file \
  --version v3 \
  --domain-subdir \
  --source /traefik/acme.json \
  --dest /certs \
  --watch

# --- Summary ---
echo ""
echo "-----------------------------------------"
echo "Deployment Summary"
echo "-----------------------------------------"
echo "Traefik Container: $TRAEFIK_CONTAINER_NAME"
echo "  - HTTP Port:  $HTTP_PORT"
echo "  - HTTPS Port: $HTTPS_PORT"
echo "Certs Dumper Container: $CERTS_DUMPER_CONTAINER_NAME"
echo "  - Watching:   $TRAEFIK_ACME_FILE_PATH"
echo "  - Dumping to: $TRAEFIK_CERTS_DUMP_PATH"
echo "-----------------------------------------"
echo "Deployment complete."
