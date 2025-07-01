#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script (Single Env File)
# ======================================================================
# Uses unified .env for both Traefik static config and script-specific vars

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Unified environment file
ENV_FILE="../secrets/traefik.env"

# Check env file exists
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Missing environment file at $ENV_FILE"
  exit 1
fi

# Export environment
set -o allexport
source "$ENV_FILE"
set +o allexport

# Validate required vars
: "${TRAEFIK_CONTAINER_NAME:?TRAEFIK_CONTAINER_NAME must be set}"
: "${TRAEFIK_IMAGE:?TRAEFIK_IMAGE must be set}"
: "${TRAEFIK_NETWORK:?TRAEFIK_NETWORK must be set}"
: "${TRAEFIK_PROVIDERS_DOCKER_NETWORK:?TRAEFIK_PROVIDERS_DOCKER_NETWORK must be set}"
: "${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS:?TRAEFIK_ENTRYPOINTS_WEB_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS:?TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS:?TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS:?TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS must be set}"
: "${TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL:?ACME email must be set}"

# Compute host ports
HTTP_PORT="${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS#:}"
HTTPS_PORT="${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS#:}"
METRICS_PORT="${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS#:}"
DASHBOARD_PORT="${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS#:}"

# Create network
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || true

# Prepare acme.json
touch "$SCRIPT_DIR/acme.json" && chmod 600 "$SCRIPT_DIR/acme.json"

# Remove old container
docker rm -f "$TRAEFIK_CONTAINER_NAME" 2>/dev/null || true

# Pull image
docker pull "$TRAEFIK_IMAGE"

# Run container
docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart=always \
  --network="$TRAEFIK_NETWORK" \
  --env-file="$ENV_FILE" \
  -p "$HTTP_PORT":80 \
  -p "$HTTPS_PORT":443 \
  -p "$METRICS_PORT":9100 \
  -p "$DASHBOARD_PORT":8083 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$SCRIPT_DIR/acme.json":/etc/traefik/acme.json:ro \
  -v "$SCRIPT_DIR/traefik.yml":/etc/traefik/traefik.yml:ro \
  -v "$SCRIPT_DIR/redirect.yml":/etc/traefik/redirect.yml:ro \
  "$TRAEFIK_IMAGE"

# Summary
echo "Traefik '$TRAEFIK_CONTAINER_NAME' deployed"
echo "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Metrics=$METRICS_PORT, Dashboard=$DASHBOARD_PORT"
