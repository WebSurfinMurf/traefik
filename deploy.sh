#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script
# ======================================================================
# Description:
#   Deploys Traefik reverse proxy with Docker, using external .env
#   and a traefik.yml static config.

# Ensure script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Path to your environment file
ENV_FILE="../secrets/traefik.env"

# Pre-flight: ensure .env exists
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Environment file not found at $ENV_FILE"
  exit 1
fi
source "$ENV_FILE"

# Required vars check
: "${TRAEFIK_CONTAINER_NAME:?}"
: "${TRAEFIK_IMAGE:?}"
: "${TRAEFIK_NETWORK:?}"
: "${TRAEFIK_WEB_PORT:?}"
: "${TRAEFIK_WEBSECURE_PORT:?}"
: "${TRAEFIK_METRICS_PORT:?}"
: "${TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL:?}"

# Create network
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || \
  echo "Network '$TRAEFIK_NETWORK' already exists."

# Prepare acme.json
touch "$SCRIPT_DIR/acme.json"
chmod 600 "$SCRIPT_DIR/acme.json"

# Clean up existing container
if docker ps -q -f name="$TRAEFIK_CONTAINER_NAME" | grep -q .; then
  docker stop "$TRAEFIK_CONTAINER_NAME"
  docker rm "$TRAEFIK_CONTAINER_NAME"
fi

# Pull image
docker pull "$TRAEFIK_IMAGE"

# Run container
docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart always \
  --network "$TRAEFIK_NETWORK" \
  --env-file "$ENV_FILE" \
  -p "$TRAEFIK_WEB_PORT":80 \
  -p "$TRAEFIK_WEBSECURE_PORT":443 \
  -p "$TRAEFIK_METRICS_PORT":9100 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$SCRIPT_DIR/acme.json":/etc/traefik/acme.json \
  -v "$SCRIPT_DIR/traefik.yml":/etc/traefik/traefik.yml:ro \
  "$TRAEFIK_IMAGE"

echo "Traefik deployed: $TRAEFIK_CONTAINER_NAME"
echo "Dashboard: http://localhost:8080"
echo "Metrics: http://localhost:$TRAEFIK_METRICS_PORT/metrics"
echo "Web (HTTP): port $TRAEFIK_WEB_PORT"
echo "Websecure (HTTPS): port $TRAEFIK_WEBSECURE_PORT"
