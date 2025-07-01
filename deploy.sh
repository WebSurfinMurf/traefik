#!/usr/bin/env bash

# ======================================================================
# Traefik Deployment Script (Items 1-4)
# ======================================================================
# Implements:
#   1. Dynamic HTTP→HTTPS redirects via redirect.yml (excluding ACME paths)
#   2. DNS‑01 challenge fallback via dns.yml and env vars
#   3. Docker labels on services (note: apply labels in each service’s compose/docker run)
#   4. Health checks to auto-restart Traefik if unhealthy

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

# Required variables
: "${TRAEFIK_CONTAINER_NAME:?}"                 # Traefik container name
: "${TRAEFIK_IMAGE:?}"                          # Traefik image (e.g., traefik:v3.4.3)
: "${TRAEFIK_NETWORK:?}"                        # Docker network for routing
: "${TRAEFIK_WEB_PORT:?}"                       # HTTP port (host)
: "${TRAEFIK_WEBSECURE_PORT:?}"                 # HTTPS port (host)
: "${TRAEFIK_METRICS_PORT:?}"                   # Prometheus metrics port (host)
: "${TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL:?}"  # ACME email
: "${TRAEFIK_DNS_PROVIDER:?}"                   # DNS-01 provider name (e.g., cloudflare)
: "${TRAEFIK_DNS_API_TOKEN:?}"                  # DNS-01 API token

# Create Docker network if needed
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || \
  echo "Network '$TRAEFIK_NETWORK' already exists."

# Prepare acme.json for Let's Encrypt storage
touch "$SCRIPT_DIR/acme.json"
chmod 600 "$SCRIPT_DIR/acme.json"

# Clean up any existing container
if docker ps -q -f name="$TRAEFIK_CONTAINER_NAME" | grep -q .; then
  docker stop "$TRAEFIK_CONTAINER_NAME"
  docker rm   "$TRAEFIK_CONTAINER_NAME"
fi

# Pull the Traefik image
docker pull "$TRAEFIK_IMAGE"

# Deploy Traefik container
docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart always \
  --network "$TRAEFIK_NETWORK" \
  --env-file "$ENV_FILE" \
  --health-cmd="curl -f http://localhost:8080/ping || exit 1" \
  --health-interval=30s \
  --health-retries=3 \
  --health-timeout=10s \
  --health-start-period=10s \
  -p "$TRAEFIK_WEB_PORT":80 \
  -p "$TRAEFIK_WEBSECURE_PORT":443 \
  -p "$TRAEFIK_METRICS_PORT":9100 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$SCRIPT_DIR/acme.json":/etc/traefik/acme.json \
  -v "$SCRIPT_DIR/traefik.yml":/etc/traefik/traefik.yml:ro \
  -v "$SCRIPT_DIR/redirect.yml":/etc/traefik/redirect.yml:ro \
  -v "$SCRIPT_DIR/dns.yml":/etc/traefik/dns.yml:ro \
  "$TRAEFIK_IMAGE"

# Summary
echo "Traefik deployed: $TRAEFIK_CONTAINER_NAME"
echo "Dashboard: http://localhost:8080"
echo "Metrics: http://localhost:$TRAEFIK_METRICS_PORT/metrics"
echo "Web (HTTP): port $TRAEFIK_WEB_PORT"
echo "Websecure (HTTPS): port $TRAEFIK_WEBSECURE_PORT"
