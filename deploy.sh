#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script (Single Env File)
# ======================================================================
# Reads Traefik static config and script-specific settings
# from a unified .env, computes host ports, and runs the Traefik container.

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

# Export all variables from env file
set -o allexport
source "$ENV_FILE"
set +o allexport

# Required variables validation
: "${TRAEFIK_CONTAINER_NAME:?TRAEFIK_CONTAINER_NAME must be set}
: "${TRAEFIK_IMAGE:?TRAEFIK_IMAGE must be set}"
: "${TRAEFIK_NETWORK:?TRAEFIK_NETWORK must be set}"
: "${TRAEFIK_PROVIDERS_DOCKER_NETWORK:?TRAEFIK_PROVIDERS_DOCKER_NETWORK must be set}"
: "${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS:?TRAEFIK_ENTRYPOINTS_WEB_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS:?TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS:?TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS must be set}"
: "${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS:?TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS must be set}"
: "${TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL:?ACME email must be set}"

# Derive host ports by stripping leading ':'
HTTP_PORT="${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS#:}"
HTTPS_PORT="${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS#:}"
METRICS_PORT="${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS#:}"
DASHBOARD_PORT="${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS#:}"

# Create Docker network if needed
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || true

# Prepare acme.json storage
touch "$SCRIPT_DIR/acme.json" && chmod 600 "$SCRIPT_DIR/acme.json"

# Remove old container if exists
docker rm -f "$TRAEFIK_CONTAINER_NAME" 2>/dev/null || true

# Pull the Traefik image
docker pull "$TRAEFIK_IMAGE"

# Run Traefik container
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

# Summary output
echo "Traefik deployed as '$TRAEFIK_CONTAINER_NAME'"
echo "HTTP      : http://<host>:$HTTP_PORT"
echo "HTTPS     : https://<host>:$HTTPS_PORT"
echo "Metrics   : http://<host>:$METRICS_PORT/metrics"
echo "Dashboard : http://<host>:$DASHBOARD_PORT"
