#!/usr/bin/env bash
set -euo pipefail

# ── Load secrets ────────────────────────────────────────────────────────
#AI: source project-specific env after pipeline.env loads
source "$(dirname "$0")/../secrets/traefik.env"

# ── Defaults and environment variables ─────────────────────────────────
TRAEFIK_IMAGE="${TRAEFIK_IMAGE:-traefik:latest}"
NETWORKS="${TRAEFIK_NETWORKS:-proxy-net,keycloak-net}"
ACME_FILE="${TRAEFIK_ACME_FILE:-/acme.json}"
CONFIG_FILE="${TRAEFIK_CONFIG_FILE:-/etc/traefik/traefik.yml}"
CONTAINER_NAME="${TRAEFIK_CONTAINER_NAME:-traefik}"

# ── Infra provisioning ─────────────────────────────────────────────────
IFS=',' read -r -a nets <<< "$NETWORKS"
for net in "${nets[@]}"; do
  if ! docker network ls --format '{{.Name}}' | grep -qx "$net"; then
    echo "Creating network $net…"
    docker network create "$net"
  fi
done

# ── Deploy Traefik ─────────────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "Removing existing Traefik container '$CONTAINER_NAME'…"
  docker rm -f "$CONTAINER_NAME"
fi

echo "Starting Traefik ($TRAEFIK_IMAGE)…"

declare -a network_flags
for net in "${nets[@]}"; do
  network_flags+=(--network "$net")
done

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  "${network_flags[@]}" \
  -p "${TRAEFIK_ENTRYPOINT_HTTP:-80}:80" \
  -p "${TRAEFIK_ENTRYPOINT_HTTPS:-443}:443" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$PWD/traefik.yml":$CONFIG_FILE:ro \
  -v "$PWD/acme.json":$ACME_FILE:ro \
  "$TRAEFIK_IMAGE"

echo "✔️ Traefik is live on ports ${TRAEFIK_ENTRYPOINT_HTTP:-80}/${TRAEFIK_ENTRYPOINT_HTTPS:-443}"
echo "Configuration file: $CONFIG_FILE"
echo "ACME storage: $ACME_FILE"
