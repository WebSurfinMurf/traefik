#!/usr/bin/env bash
set -euxo pipefail

# ── Load secrets ────────────────────────────────────────────────────────
#AI: source project-specific env after pipeline.env loads
source "$(dirname "$0")/../secrets/traefik.env"

# ── Infra provisioning ─────────────────────────────────────────────────
NETWORK="${TRAEFIK_NETWORK:-proxy-net}"  # Docker network for proxy and services
ACME_FILE="${TRAEFIK_ACME_FILE:-/acme.json}"
CONFIG_FILE="${TRAEFIK_CONFIG_FILE:-/etc/traefik/traefik.yml}"
CONTAINER_NAME="${TRAEFIK_CONTAINER_NAME:-traefik}"

# ensure network exists
if ! docker network ls --format '{{.Name}}' | grep -qx "${NETWORK}"; then
  echo "Creating network ${NETWORK}…"
  docker network create "${NETWORK}"
fi

# ── Deploy Traefik ─────────────────────────────────────────────────────
# remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "Removing existing Traefik container '${CONTAINER_NAME}'…"
  docker rm -f "${CONTAINER_NAME}"
fi

echo "Starting Traefik (${TRAEFIK_IMAGE:-traefik:latest})…"
docker run -d \
  --name "${CONTAINER_NAME}" \
  --network "${NETWORK}" \
  --restart unless-stopped \
  -p "${TRAEFIK_ENTRYPOINT_HTTP:-80}:80" \
  -p "${TRAEFIK_ENTRYPOINT_HTTPS:-443}:443" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$PWD/traefik.yml":${CONFIG_FILE} \
  -v "$PWD/acme.json":${ACME_FILE} \
  "${TRAEFIK_IMAGE:-traefik:latest}"

echo "✔️ Traefik is live on ports ${TRAEFIK_ENTRYPOINT_HTTP:-80}/${TRAEFIK_ENTRYPOINT_HTTPS:-443}" 

echo "Configuration file: ${CONFIG_FILE}" 
echo "ACME storage: ${ACME_FILE}"
