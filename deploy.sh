#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script (Single Env File)
# ======================================================================
# Uses a unified .env for both Traefik static config and script-specific vars
# Computes host ports, ensures necessary files, and starts the Traefik container.

# Ensure script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Path to the unified environment file
ENV_FILE="../secrets/traefik.env"

# Pre-flight: ensure env file exists
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Environment file not found at $ENV_FILE"
  exit 1
fi

# Source all variables from env file
set -o allexport
source "$ENV_FILE"
set +o allexport

# Validate required script variables
: "${TRAEFIK_CONTAINER_NAME:?TRAEFIK_CONTAINER_NAME must be set}"
: "${TRAEFIK_IMAGE:?TRAEFIK_IMAGE must be set}"
: "${TRAEFIK_NETWORK:?TRAEFIK_NETWORK must be set}"

# Compute host ports by stripping the leading ':' from entryPoint values
HTTP_PORT="${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS#:}"
HTTPS_PORT="${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS#:}"
METRICS_PORT="${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS#:}"
DASHBOARD_PORT="${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS#:}"

# Create Docker network if it doesn't exist
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || true

# Prepare acme.json file for Let's Encrypt storage
touch "$SCRIPT_DIR/acme.json" && chmod 600 "$SCRIPT_DIR/acme.json"

# Remove existing container if present
docker rm -f "$TRAEFIK_CONTAINER_NAME" 2>/dev/null || true

# Pull the specified Traefik image
docker pull "$TRAEFIK_IMAGE"

# Run the Traefik container with proper mounts and port mappings
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
  -v "$SCRIPT_DIR/acme.json":/etc/traefik/acme.json:rw \
  -v "$SCRIPT_DIR/traefik.yml":/etc/traefik/traefik.yml:ro \
  -v "$SCRIPT_DIR/redirect.yml":/etc/traefik/redirect.yml:ro \
  "$TRAEFIK_IMAGE"

# Summary output
echo "Traefik '$TRAEFIK_CONTAINER_NAME' deployed"
echo "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Metrics=$METRICS_PORT, Dashboard=$DASHBOARD_PORT"
