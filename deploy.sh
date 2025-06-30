#!/usr/bin/env bash
set -euxo pipefail

# ── deploy.sh ──────────────────────────────────────────────────────────
# This script deploys Traefik as a reverse proxy container with dashboard, logs, and metrics.
# Place this file at projects/traefik/deploy.sh and ensure it's executable.

# ── Load secrets ────────────────────────────────────────────────────────
#AI: source project-specific env after pipeline.env loads
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
source "${BASEDIR}/../secrets/traefik.env"

# ── Defaults and environment variables ─────────────────────────────────
TRAEFIK_IMAGE="${TRAEFIK_IMAGE:-traefik:latest}"
NETWORKS="${TRAEFIK_NETWORKS:-proxy-net,keycloak-net}"
ACME_FILE="${TRAEFIK_ACME_FILE:-/acme.json}"
CONFIG_FILE="${TRAEFIK_CONFIG_FILE:-/etc/traefik/traefik.yml}"
CONTAINER_NAME="${TRAEFIK_CONTAINER_NAME:-traefik}"
DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-8088}"
LOG_LEVEL="${TRAEFIK_LOG_LEVEL:-INFO}"
METRICS_PORT="${TRAEFIK_METRICS_PORT:-9100}"

# Determine bind address (default to all interfaces)
BIND_ADDRESS="${TRAEFIK_BIND_ADDRESS:-0.0.0.0}"

# ── Infra provisioning ─────────────────────────────────────────────────
IFS=',' read -r -a nets <<< "${NETWORKS}"
for net in "${nets[@]}"; do
  if ! docker network ls --format '{{.Name}}' | grep -qx "${net}"; then
    echo "Creating network ${net}…"
    docker network create "${net}"
  fi
done

# ── Deploy Traefik ─────────────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "Removing existing Traefik container '${CONTAINER_NAME}'…"
  docker rm -f "${CONTAINER_NAME}"
fi

echo "Preparing to start Traefik container with the following command:"

# Build run command
declare -a run_cmd=(docker run -d --name "${CONTAINER_NAME}" --restart unless-stopped)
declare -a docker_flags=(
  # attach to networks
  $(for net in "${nets[@]}"; do echo "--network ${net}"; done)
  # ports: host->container (bind to all or specified address)
  -p "${BIND_ADDRESS}:${TRAEFIK_ENTRYPOINT_HTTP}:80"      # HTTP entrypoint
  -p "${BIND_ADDRESS}:${TRAEFIK_ENTRYPOINT_HTTPS}:443"    # HTTPS entrypoint
  -p "${BIND_ADDRESS}:${DASHBOARD_PORT}:8080"             # dashboard API
  -p "${BIND_ADDRESS}:${METRICS_PORT}:9100"              # Prometheus metrics endpoint
  # volumes
  -v /var/run/docker.sock:/var/run/docker.sock:ro
  -v "${BASEDIR}/traefik.yml":${CONFIG_FILE}:ro
  -v "${BASEDIR}/acme.json":${ACME_FILE}:ro
  # image
  "${TRAEFIK_IMAGE}"
  # core flags
  --log.level="${LOG_LEVEL}" \
  --api.dashboard=true \
  --api.insecure=true \
  # entryPoints
  --entryPoints.web.address=":80" \
  --entryPoints.websecure.address=":443" \
  --entryPoints.traefik.address=":${DASHBOARD_PORT}" \
  --entryPoints.metrics.address=":${METRICS_PORT}" \
  # providers
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  # certificates
  --certificatesResolvers.le.acme.email="${TRAEFIK_ACME_EMAIL}" \
  --certificatesResolvers.le.acme.storage="${ACME_FILE}" \
  --certificatesResolvers.le.acme.httpChallenge.entryPoint=web
)

# Print the full command for debugging
echo "${run_cmd[@]} ${docker_flags[@]}"

# Execute the command
"${run_cmd[@]}" "${docker_flags[@]}"

# Short pause and show recent logs for debugging
sleep 2
container_id=$(docker ps --filter "name=${CONTAINER_NAME}" -q)
echo "Logs for Traefik container (${container_id}):"
docker logs --tail 50 "$container_id"

# Confirm the container is running
if [ -n "$container_id" ] && docker inspect -f '{{.State.Running}}' "$container_id" | grep -q true; then
  echo "✔️ Traefik container is running"
else
  echo "❌ Traefik failed to start. Inspect the logs above for errors."
fi
