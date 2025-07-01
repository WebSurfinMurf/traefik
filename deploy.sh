#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script (Items 1-4)
# ======================================================================
# This script deploys Traefik using Docker,
# leveraging a unified environment file for Traefik configuration
# and script-specific variables for container settings.

# Ensure script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Path to the unified Traefik env file
ENV_FILE="../secrets/traefik.env"

# Ensure the env file exists
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Traefik env file not found at $ENV_FILE"
  exit 1
fi
# Load Traefik configuration variables
env | grep TRAEFIK_
# We won't source to avoid polluting script namespace

# Script-specific variables (must be set in the shell or another env file)
: "${TRAEFIK_CONTAINER_NAME:?TRAEFIK_CONTAINER_NAME must be set}"
: "${TRAEFIK_IMAGE:?TRAEFIK_IMAGE must be set}"
: "${TRAEFIK_NETWORK:?TRAEFIK_NETWORK must be set}"
: "${TRAEFIK_DASHBOARD_PORT:?TRAEFIK_DASHBOARD_PORT must be set}"

# Create Docker network if it doesn't exist
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || true

# Prepare ACME storage
touch "$SCRIPT_DIR/acme.json"
chmod 600 "$SCRIPT_DIR/acme.json"

# Remove any existing container
docker rm -f "$TRAEFIK_CONTAINER_NAME" 2>/dev/null || true

# Pull the Traefik image
docker pull "$TRAEFIK_IMAGE"

# Run Traefik container with unified env and mounts
docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart always \
  --network "$TRAEFIK_NETWORK" \
  --env-file "$ENV_FILE" \
  -p 80:80 \
  -p 443:443 \
  -p 9100:9100 \
  -p "$TRAEFIK_DASHBOARD_PORT":8083 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$SCRIPT_DIR/acme.json":/etc/traefik/acme.json:ro \
  -v "$SCRIPT_DIR/traefik.yml":/etc/traefik/traefik.yml:ro \
  -v "$SCRIPT_DIR/redirect.yml":/etc/traefik/redirect.yml:ro \
  "$TRAEFIK_IMAGE"

# Display deployment info
echo "Traefik deployed as container '$TRAEFIK_CONTAINER_NAME'"
echo "Dashboard available at http://<host>:$TRAEFIK_DASHBOARD_PORT"
echo "Metrics at http://<host>:9100/metrics"
echo "HTTP  : http://<host>:80"
echo "HTTPS : https://<host>"
