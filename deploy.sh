#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script (Single Env File)
# ======================================================================
# Reads both Traefik static config and script-specific settings
# from one unified .env, computes host ports from entrypoint vars,
# and runs the Traefik Docker container.

# Ensure script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Path to the unified Traefik env file
ENV_FILE="../secrets/traefik.env"

# Pre-flight: ensure env file exists
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Environment file not found at $ENV_FILE"
  exit 1
fi

# Load all variables from the env file into the shell
set -o allexport
source "$ENV_FILE"
set +o allexport

# Required script-specific variables
: "${TRAEFIK_CONTAINER_NAME:?TRAEFIK_CONTAINER_NAME must be set in env file}"
: "${TRAEFIK_IMAGE:?TRAEFIK_IMAGE must be set in env file}"
: "${TRAEFIK_NETWORK:?TRAEFIK_NETWORK must be set in env file}"

# Derive host ports by stripping leading colon
HTTP_PORT="${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS#:}"
HTTPS_PORT="${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS#:}"
METRICS_PORT="${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS#:}"
DASHBOARD_PORT="${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS#:}"

# Create Docker network if needed
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || true

# Prepare acme.json for Let's Encrypt storage
touch "$SCRIPT_DIR/acme.json" && chmod 600 "$SCRIPT_DIR/acme.json"

# Remove any existing container
docker rm -f "$TRAEFIK_CONTAINER_NAME" 2>/dev/null || true

# Pull the Traefik image
docker pull "$TRAEFIK_IMAGE"

# --providers.docker.network=traefik-proxy \
# Run the Traefik container
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
echo "Traefik deployed as '$TRAEFIK_CONTAINER_NAME'"
echo "HTTP      : http://<host>:$HTTP_PORT"
echo "HTTPS     : https://<host>:$HTTPS_PORT"
echo "Metrics   : http://<host>:$METRICS_PORT/metrics"
echo "Dashboard : http://<host>:$DASHBOARD_PORT"
