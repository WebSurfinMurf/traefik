#!/bin/bash
set -e

echo "🚀 Deploying Traefik Reverse Proxy"
echo "===================================="
echo ""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Environment file
ENV_FILE="$HOME/projects/secrets/traefik.env"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Pre-deployment Checks ---
echo "🔍 Pre-deployment checks..."

# Check if network exists
if ! docker network inspect traefik-net &>/dev/null; then
    echo -e "${RED}❌ traefik-net network not found${NC}"
    echo "Run: /home/administrator/projects/infrastructure/setup-networks.sh"
    exit 1
fi
echo -e "${GREEN}✅ traefik-net network exists${NC}"

# Check environment file
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Environment file not found: $ENV_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Environment file exists${NC}"

# Check required config files
if [ ! -f "$SCRIPT_DIR/traefik.yml" ]; then
    echo -e "${RED}❌ traefik.yml not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ traefik.yml exists${NC}"

if [ ! -f "$SCRIPT_DIR/redirect.yml" ]; then
    echo -e "${RED}❌ redirect.yml not found${NC}"
    exit 1
fi
echo -e "${GREEN}✅ redirect.yml exists${NC}"

# Source environment variables
set -o allexport
source "$ENV_FILE"
set +o allexport

# Prepare acme.json file
echo ""
echo "📁 Preparing certificate storage..."
if [ ! -f "$TRAEFIK_ACME_FILE_PATH" ]; then
    touch "$TRAEFIK_ACME_FILE_PATH"
    echo -e "${GREEN}✅ Created acme.json${NC}"
fi
chmod 600 "$TRAEFIK_ACME_FILE_PATH"
echo -e "${GREEN}✅ acme.json permissions set (600)${NC}"

# Prepare certificate dump directory
mkdir -p "$TRAEFIK_CERTS_DUMP_PATH"
echo -e "${GREEN}✅ Certificate dump directory ready${NC}"

# Validate docker-compose.yml syntax
echo ""
echo "✅ Validating docker-compose.yml..."
if ! docker compose config > /dev/null 2>&1; then
    echo -e "${RED}❌ docker-compose.yml validation failed${NC}"
    docker compose config
    exit 1
fi
echo -e "${GREEN}✅ docker-compose.yml is valid${NC}"

# --- Deployment ---
echo ""
echo "🚀 Deploying Traefik services..."
docker compose up -d --remove-orphans

# --- Post-deployment Validation ---
echo ""
echo "⏳ Waiting for Traefik to start..."
sleep 5

# Check if Traefik is running
if ! docker ps | grep -q "$TRAEFIK_CONTAINER_NAME"; then
    echo -e "${RED}❌ Traefik container not running${NC}"
    docker logs "$TRAEFIK_CONTAINER_NAME" --tail 50
    exit 1
fi
echo -e "${GREEN}✅ Traefik container is running${NC}"

# Check Traefik health
echo "🔍 Checking Traefik health..."
HEALTH_CHECK_ATTEMPTS=0
MAX_ATTEMPTS=10

while [ $HEALTH_CHECK_ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    if docker exec "$TRAEFIK_CONTAINER_NAME" wget -qO- http://localhost:8083/api/version 2>/dev/null | grep -q "Version"; then
        echo -e "${GREEN}✅ Traefik is healthy${NC}"
        break
    fi
    HEALTH_CHECK_ATTEMPTS=$((HEALTH_CHECK_ATTEMPTS + 1))
    if [ $HEALTH_CHECK_ATTEMPTS -eq $MAX_ATTEMPTS ]; then
        echo -e "${RED}❌ Traefik health check failed after $MAX_ATTEMPTS attempts${NC}"
        docker logs "$TRAEFIK_CONTAINER_NAME" --tail 30
        exit 1
    fi
    echo "   Attempt $HEALTH_CHECK_ATTEMPTS/$MAX_ATTEMPTS..."
    sleep 2
done

# Check if certs-dumper is running
if ! docker ps | grep -q "$CERTS_DUMPER_CONTAINER_NAME"; then
    echo -e "${YELLOW}⚠️  Certs dumper container not running (non-critical)${NC}"
else
    echo -e "${GREEN}✅ Certs dumper container is running${NC}"
fi

# --- Summary ---
echo ""
echo "=========================================="
echo "✅ Traefik Deployment Summary"
echo "=========================================="
echo "Container: $TRAEFIK_CONTAINER_NAME"
echo "Image: $TRAEFIK_IMAGE"
echo "Network: traefik-net"
echo ""
echo "Entry Points:"
echo "  - HTTP:       ${TRAEFIK_ENTRYPOINTS_WEB_ADDRESS:-:80}"
echo "  - HTTPS:      ${TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS:-:443}"
echo "  - Dashboard:  ${TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS:-:8083}"
echo "  - Metrics:    ${TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS:-:9100}"
echo "  - SMTP:       ${TRAEFIK_ENTRYPOINTS_SMTP_ADDRESS:-:25}"
echo "  - SMTPS:      ${TRAEFIK_ENTRYPOINTS_SMTPS_ADDRESS:-:465}"
echo "  - Submission: ${TRAEFIK_ENTRYPOINTS_SUBMISSION_ADDRESS:-:587}"
echo "  - IMAPS:      ${TRAEFIK_ENTRYPOINTS_IMAPS_ADDRESS:-:993}"
echo ""
echo "Access Points:"
echo "  - Dashboard: https://traefik.ai-servicers.com:8083"
echo "  - API:       http://localhost:8083/api/http/routers"
echo "  - Metrics:   http://localhost:9100/metrics"
echo ""
echo "Certificates:"
echo "  - Storage:   $TRAEFIK_ACME_FILE_PATH"
echo "  - Dumps:     $TRAEFIK_CERTS_DUMP_PATH"
echo "=========================================="
echo ""
echo "📊 View logs:"
echo "   docker logs $TRAEFIK_CONTAINER_NAME -f"
echo ""
echo "🔍 Check routers:"
echo "   docker exec $TRAEFIK_CONTAINER_NAME wget -qO- http://localhost:8083/api/http/routers | jq"
echo ""
echo "✅ Deployment complete!"
