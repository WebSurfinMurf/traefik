#!/bin/bash
# Post-deploy health check for Traefik.
#
# Verifies Traefik is running and responding on its API endpoint.
# Polls with retries since the container may take a moment after recreate.
set -euo pipefail

CONTAINER="${TRAEFIK_CONTAINER_NAME:-traefik}"
RETRIES="${HEALTHCHECK_RETRIES:-15}"
INTERVAL="${HEALTHCHECK_INTERVAL:-4}"

echo "Waiting for Traefik API (up to $((RETRIES * INTERVAL))s) ..."
for i in $(seq 1 "$RETRIES"); do
    if docker exec "$CONTAINER" wget -qO- http://localhost:8083/api/version 2>/dev/null | grep -q "Version"; then
        echo "Traefik API responding after ${i} attempt(s)"
        break
    fi
    if [ "$i" -eq "$RETRIES" ]; then
        echo "ERROR: Traefik API never came up" >&2
        docker logs "$CONTAINER" --tail 30
        exit 1
    fi
    sleep "$INTERVAL"
done

# Verify routers are loaded (docker provider discovers containers)
ROUTER_COUNT=$(docker exec "$CONTAINER" wget -qO- http://localhost:8083/api/http/routers 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "HTTP routers loaded: $ROUTER_COUNT"
if [ "$ROUTER_COUNT" -lt 1 ]; then
    echo "WARNING: No HTTP routers loaded — docker provider may not be connected"
    exit 1
fi

echo "Healthcheck OK"
