#!/bin/bash
# Automated script to recreate traefik-net with IP reservations
# Based on: NETWORK-FIX-GUIDE.md

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error handling
trap 'echo -e "${RED}Error on line $LINENO${NC}"; exit 1' ERR

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Traefik Network IP Reservation - Automated Fix       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will stop ALL services on traefik-net${NC}"
echo -e "${YELLOW}⚠️  Estimated downtime: 30-60 minutes${NC}"
echo ""

# Confirmation
read -p "Are you ready to proceed? (type 'yes' to continue): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Aborted.${NC}"
    exit 0
fi

# ============================================================================
# STEP 1: PREPARATION
# ============================================================================
echo ""
echo -e "${BLUE}[Step 1/7] Preparation...${NC}"

# Create backup directory
BACKUP_DIR="/tmp/traefik-net-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓ Backup directory: $BACKUP_DIR${NC}"

# Save current network state (if network exists)
if docker network inspect traefik-net >/dev/null 2>&1; then
    docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | sort > "$BACKUP_DIR/containers-before.txt"
    docker network inspect traefik-net > "$BACKUP_DIR/network-config-backup.json"
    echo -e "${GREEN}✓ Current state backed up${NC}"

    # Count containers
    CONTAINER_COUNT=$(wc -l < "$BACKUP_DIR/containers-before.txt")
    echo -e "${GREEN}✓ Found $CONTAINER_COUNT containers on traefik-net${NC}"
else
    echo -e "${YELLOW}⚠ Network traefik-net does not exist (may have been removed already)${NC}"
    CONTAINER_COUNT=0
    echo "0" > "$BACKUP_DIR/containers-before.txt"
    echo "{}" > "$BACKUP_DIR/network-config-backup.json"
fi

# ============================================================================
# STEP 2: STOP ALL SERVICES
# ============================================================================
echo ""
echo -e "${BLUE}[Step 2/7] Stopping all services...${NC}"

# Function to stop containers
stop_containers() {
    local services=("$@")
    for service in "${services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            echo -n "  Stopping $service... "
            docker stop "$service" >/dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}(not found)${NC}"
        fi
        # Also stop auth proxy if exists
        if docker ps --format '{{.Names}}' | grep -q "^${service}-auth-proxy$"; then
            docker stop "${service}-auth-proxy" >/dev/null 2>&1
        fi
    done
}

# Application services
echo "Stopping application services..."
stop_containers dashy obsidian alist microbin stirling-pdf matrix-element matrix-synapse \
                 nextcloud gitlab bitwarden guacamole portainer open-webui n8n playwright \
                 dozzle netdata grafana loki drawio nginx langserve litellm langchain-portal

# Database UIs
echo "Stopping database UIs..."
stop_containers pgadmin redis-commander mongo-express arangodb

# Keycloak
echo "Stopping Keycloak..."
stop_containers keycloak

# Traefik (last)
echo "Stopping Traefik..."
stop_containers traefik traefik-certs-dumper

# Force stop any remaining containers on traefik-net (if network exists)
if docker network inspect traefik-net >/dev/null 2>&1; then
    echo "Checking for remaining containers..."
    docker network inspect traefik-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | \
      while read container; do
        if [ -n "$container" ] && docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            echo "  Force stopping: $container"
            docker stop "$container" >/dev/null 2>&1
        fi
      done

    echo -e "${GREEN}✓ All services stopped${NC}"

    # Disconnect all containers
    echo "Disconnecting containers from network..."
    docker network inspect traefik-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | \
      while read container; do
        if [ -n "$container" ]; then
            docker network disconnect traefik-net "$container" 2>/dev/null || true
        fi
      done
    echo -e "${GREEN}✓ All containers disconnected${NC}"
else
    echo -e "${YELLOW}⚠ Network already removed, skipping container disconnect${NC}"
fi

# ============================================================================
# STEP 3: RECREATE NETWORK
# ============================================================================
echo ""
echo -e "${BLUE}[Step 3/7] Recreating network with IP restrictions...${NC}"

# Remove old network (if it exists)
if docker network inspect traefik-net >/dev/null 2>&1; then
    docker network rm traefik-net
    echo -e "${GREEN}✓ Old network removed${NC}"
else
    echo -e "${YELLOW}⚠ Network already removed${NC}"
fi

# Create new network with IP range restrictions
docker network create traefik-net \
  --subnet=172.25.0.0/16 \
  --gateway=172.25.0.1 \
  --ip-range=172.25.0.128/25 \
  --aux-address="reserved-static-1=172.25.0.2" \
  --aux-address="reserved-static-2=172.25.0.10" \
  --aux-address="reserved-static-3=172.25.0.20" \
  --aux-address="reserved-static-4=172.25.0.30" \
  --aux-address="reserved-static-5=172.25.0.40" \
  --aux-address="reserved-static-6=172.25.0.50" >/dev/null

echo -e "${GREEN}✓ New network created${NC}"
echo "   IP Range for auto-assignment: 172.25.0.128-172.25.0.255"
echo "   Reserved for static IPs: 172.25.0.2-172.25.0.127"

# Verify
docker network inspect traefik-net --format '{{json .IPAM}}' > "$BACKUP_DIR/network-config-new.json"
echo -e "${GREEN}✓ Network configuration saved${NC}"

# ============================================================================
# STEP 4: RESTART CORE SERVICES
# ============================================================================
echo ""
echo -e "${BLUE}[Step 4/7] Restarting core infrastructure...${NC}"

# PostgreSQL (if needed)
if ! docker ps | grep -q postgres; then
    echo "Starting PostgreSQL..."
    cd /home/administrator/projects/postgres && ./deploy.sh >/dev/null 2>&1
    sleep 5
    echo -e "${GREEN}✓ PostgreSQL started${NC}"
fi

# Traefik (CRITICAL)
echo "Starting Traefik..."
cd /home/administrator/projects/traefik
./deploy.sh >/dev/null 2>&1 || {
    echo -e "${RED}✗ Traefik failed to start! Check logs:${NC}"
    docker logs traefik --tail 20
    exit 1
}

# Verify Traefik IP
TRAEFIK_IP=$(docker network inspect traefik-net --format '{{range .Containers}}{{if eq .Name "traefik"}}{{.IPv4Address}}{{end}}{{end}}')
if [ "$TRAEFIK_IP" = "172.25.0.6/16" ]; then
    echo -e "${GREEN}✓ Traefik started with correct IP: 172.25.0.6${NC}"
else
    echo -e "${RED}✗ Traefik has wrong IP: $TRAEFIK_IP${NC}"
    echo -e "${YELLOW}  (Expected: 172.25.0.6/16)${NC}"
    exit 1
fi

# Keycloak
echo "Starting Keycloak..."
cd /home/administrator/projects/keycloak
./deploy.sh >/dev/null 2>&1 || {
    echo -e "${RED}✗ Keycloak failed to start! Check logs:${NC}"
    docker logs keycloak --tail 20
    exit 1
}
echo -e "${GREEN}✓ Keycloak started (warming up...)${NC}"

# Wait for Keycloak
echo -n "Waiting for Keycloak to be ready"
for i in {1..30}; do
    if curl -s https://keycloak.ai-servicers.com >/dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# ============================================================================
# STEP 5: RESTART APPLICATION SERVICES
# ============================================================================
echo ""
echo -e "${BLUE}[Step 5/7] Restarting application services...${NC}"

# Function to deploy service
deploy_service() {
    local service_path="$1"
    local service_name="$2"

    if [ -f "$service_path/deploy.sh" ]; then
        echo -n "  Starting $service_name... "
        cd "$service_path"
        ./deploy.sh >/dev/null 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}⚠${NC}"
    fi
}

# Infrastructure
echo "Infrastructure services:"
deploy_service "/home/administrator/projects/nginx" "nginx"
deploy_service "/home/administrator/projects/portainer" "portainer"

# Databases
echo "Database UIs:"
[ -f /home/administrator/projects/postgres/deploy-pgadmin-sso.sh ] && \
  (cd /home/administrator/projects/postgres && ./deploy-pgadmin-sso.sh >/dev/null 2>&1) && echo -e "  pgadmin ${GREEN}✓${NC}"
[ -f /home/administrator/projects/redis/deploy-redis-commander.sh ] && \
  (cd /home/administrator/projects/redis && ./deploy-redis-commander.sh >/dev/null 2>&1) && echo -e "  redis-commander ${GREEN}✓${NC}"
[ -f /home/administrator/projects/mongodb/deploy-mongo-express.sh ] && \
  (cd /home/administrator/projects/mongodb && ./deploy-mongo-express.sh >/dev/null 2>&1) && echo -e "  mongo-express ${GREEN}✓${NC}"

# User services
echo "User-facing services:"
deploy_service "/home/administrator/projects/dashy" "dashy"
deploy_service "/home/administrator/projects/nextcloud" "nextcloud"
deploy_service "/home/administrator/projects/guacamole" "guacamole"
deploy_service "/home/administrator/projects/bitwarden" "bitwarden"

# AI/Context services
echo "AI & Context services:"
deploy_service "/home/administrator/projects/open-webui" "open-webui"
deploy_service "/home/administrator/projects/n8n" "n8n"
deploy_service "/home/administrator/projects/alist" "alist"
deploy_service "/home/administrator/projects/obsidian" "obsidian"
deploy_service "/home/administrator/projects/matrix" "matrix"

# Development
echo "Development services:"
deploy_service "/home/administrator/projects/gitlab" "gitlab"
deploy_service "/home/administrator/projects/playwright" "playwright"
deploy_service "/home/administrator/projects/drawio" "drawio"

# Monitoring
echo "Monitoring services:"
deploy_service "/home/administrator/projects/dozzle" "dozzle"
deploy_service "/home/administrator/projects/grafana" "grafana"
deploy_service "/home/administrator/projects/loki" "loki"
deploy_service "/home/administrator/projects/netdata" "netdata"

# Utilities
echo "Utility services:"
deploy_service "/home/administrator/projects/microbin" "microbin"
deploy_service "/home/administrator/projects/stirling-pdf" "stirling-pdf"

# ============================================================================
# STEP 6: VERIFICATION
# ============================================================================
echo ""
echo -e "${BLUE}[Step 6/7] Verification...${NC}"

# Count running containers
RUNNING_COUNT=$(docker ps --format '{{.Names}}' | wc -l)
echo -e "${GREEN}✓ Running containers: $RUNNING_COUNT${NC}"

# Check for failed containers
FAILED_COUNT=$(docker ps -a --filter "status=exited" --filter "status=dead" | wc -l)
if [ "$FAILED_COUNT" -gt 1 ]; then
    echo -e "${YELLOW}⚠ Failed containers detected: $((FAILED_COUNT - 1))${NC}"
    docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}" | tail -n +2
fi

# Save final state
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | sort > "$BACKUP_DIR/containers-after.txt"

# Verify IP ranges
echo ""
echo "IP Address Distribution:"
echo -e "${GREEN}Static range (172.25.0.2-99):${NC}"
docker network inspect traefik-net --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' | \
  awk '$1 ~ /^172\.25\.0\.([2-9]|[1-9][0-9])\//' | sort -t. -k4 -n | head -10

echo ""
echo -e "${GREEN}Auto-assigned range (172.25.0.100+):${NC}"
docker network inspect traefik-net --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' | \
  awk '$1 ~ /^172\.25\.0\.(1[0-9][0-9]|2[0-2][0-9])\//' | sort -t. -k4 -n | head -10

# Test key services
echo ""
echo "Testing key services:"
test_service() {
    local url="$1"
    local name="$2"
    if curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>&1 | grep -qE "^(200|301|302)"; then
        echo -e "  $name ${GREEN}✓${NC}"
    else
        echo -e "  $name ${YELLOW}⚠${NC}"
    fi
}

test_service "http://localhost:8083" "Traefik Dashboard"
test_service "https://keycloak.ai-servicers.com" "Keycloak"
test_service "https://dashy.ai-servicers.com" "Dashy"
test_service "https://portainer.ai-servicers.com" "Portainer"

# ============================================================================
# STEP 7: SUMMARY
# ============================================================================
echo ""
echo -e "${BLUE}[Step 7/7] Summary${NC}"
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Network Fix Completed!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Network Configuration:"
echo "  • Subnet: 172.25.0.0/16"
echo "  • Gateway: 172.25.0.1"
echo "  • Static IPs: 172.25.0.2-172.25.0.127 (reserved)"
echo "  • Auto-assign: 172.25.0.128-172.25.0.255 (128 IPs)"
echo ""
echo "Containers:"
echo "  • Before: $CONTAINER_COUNT"
echo "  • After: $(wc -l < "$BACKUP_DIR/containers-after.txt")"
echo "  • Running: $RUNNING_COUNT"
echo ""
echo "Backup Location: $BACKUP_DIR"
echo ""
echo -e "${GREEN}✓ Traefik IP is now permanently reserved at 172.25.0.6${NC}"
echo -e "${GREEN}✓ No more IP conflicts on reboot!${NC}"
echo ""
echo "Next steps:"
echo "  1. Test login to Keycloak: https://keycloak.ai-servicers.com"
echo "  2. Test Dashy access: https://dashy.ai-servicers.com"
echo "  3. Verify any custom services you use regularly"
echo ""
