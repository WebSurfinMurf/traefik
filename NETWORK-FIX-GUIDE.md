# Permanent traefik-net IP Reservation Fix

## Overview
This guide recreates the `traefik-net` Docker network with IP range restrictions to permanently prevent IP conflicts.

**Estimated Time:** 30-60 minutes
**Downtime:** All services on traefik-net will be offline during the process

## What This Does
- Reserves **172.25.0.2-172.25.0.127** for static IP assignments
- Allows automatic assignment only from **172.25.0.128-172.25.0.255**
- Prevents containers from grabbing Traefik's IP (172.25.0.6)

## Pre-Requisites
- [ ] All deploy scripts in `/home/administrator/projects/` must be executable and working
- [ ] Keycloak admin credentials available (will need to log in after restart)
- [ ] Schedule during low-usage time (services will be down ~30-60 min)

---

## Step 1: Preparation (5 minutes)

### 1.1 Document Current State
```bash
# Save list of all containers on traefik-net
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | sort > /tmp/traefik-net-before.txt

# Review what will be affected
cat /tmp/traefik-net-before.txt

# Count containers
wc -l /tmp/traefik-net-before.txt
```

### 1.2 Verify Deploy Scripts
```bash
# Check critical deploy scripts exist
ls -lh /home/administrator/projects/traefik/deploy.sh
ls -lh /home/administrator/projects/keycloak/deploy.sh
ls -lh /home/administrator/projects/postgres/deploy.sh
ls -lh /home/administrator/projects/nginx/deploy.sh

# Ensure they're executable
chmod +x /home/administrator/projects/*/deploy.sh
```

### 1.3 Create Backup
```bash
# Backup current network configuration
docker network inspect traefik-net > /tmp/traefik-net-backup.json
```

---

## Step 2: Stop All Services (10 minutes)

### 2.1 Stop Services in Reverse Dependency Order
```bash
# Stop application services first (depend on Keycloak/Postgres)
echo "Stopping application services..."
for service in dashy obsidian alist microbin stirling-pdf matrix-element matrix-synapse \
               nextcloud gitlab bitwarden guacamole portainer open-webui n8n playwright \
               dozzle netdata grafana loki drawio nginx langserve litellm; do
    echo "  Stopping $service..."
    docker stop ${service} 2>/dev/null || true
    docker stop ${service}-auth-proxy 2>/dev/null || true
done

# Stop database management UIs
echo "Stopping database UIs..."
docker stop pgadmin redis-commander mongo-express arangodb 2>/dev/null || true
docker stop pgadmin-auth-proxy mongo-express-auth-proxy arangodb-auth-proxy 2>/dev/null || true

# Stop Keycloak (many services depend on it)
echo "Stopping Keycloak..."
docker stop keycloak 2>/dev/null || true

# Stop Traefik last (all external access depends on it)
echo "Stopping Traefik..."
docker stop traefik traefik-certs-dumper 2>/dev/null || true

# Verify all containers on traefik-net are stopped
echo ""
echo "Remaining running containers on traefik-net:"
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | \
  while read container; do
    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
      echo "  STILL RUNNING: $container"
      docker stop "$container"
    fi
  done
```

### 2.2 Disconnect All Containers from Network
```bash
# Get list and disconnect each one
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | \
  while read container; do
    echo "Disconnecting $container..."
    docker network disconnect traefik-net "$container" 2>/dev/null || true
  done

# Verify network is empty
echo ""
echo "Containers still on traefik-net:"
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'
echo "(Should be empty)"
```

---

## Step 3: Recreate Network (2 minutes)

### 3.1 Remove Old Network
```bash
docker network rm traefik-net
echo "✓ Old network removed"
```

### 3.2 Create New Network with IP Restrictions
```bash
docker network create traefik-net \
  --subnet=172.25.0.0/16 \
  --gateway=172.25.0.1 \
  --ip-range=172.25.0.128/25 \
  --aux-address="reserved-static-1=172.25.0.2" \
  --aux-address="reserved-static-2=172.25.0.10" \
  --aux-address="reserved-static-3=172.25.0.20" \
  --aux-address="reserved-static-4=172.25.0.30" \
  --aux-address="reserved-static-5=172.25.0.40" \
  --aux-address="reserved-static-6=172.25.0.50"

echo "✓ New network created with IP restrictions"
```

### 3.3 Verify Network Configuration
```bash
docker network inspect traefik-net --format '{{json .IPAM}}' | python3 -m json.tool
```

**Expected output:**
```json
{
    "Driver": "default",
    "Options": {},
    "Config": [
        {
            "Subnet": "172.25.0.0/16",
            "IPRange": "172.25.0.128/25",
            "Gateway": "172.25.0.1",
            "AuxiliaryAddresses": {
                "reserved-static-1": "172.25.0.2",
                "reserved-static-2": "172.25.0.10",
                ...
            }
        }
    ]
}
```

---

## Step 4: Restart Core Services (15 minutes)

### 4.1 Start PostgreSQL (if not already running)
```bash
cd /home/administrator/projects/postgres
./deploy.sh

# Wait for it to be healthy
sleep 10
docker ps | grep postgres
```

### 4.2 Start Traefik (CRITICAL - Must be first on traefik-net)
```bash
cd /home/administrator/projects/traefik
./deploy.sh

# Verify it got the correct IP
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | grep traefik
# Should show: traefik - 172.25.0.6/16
```

### 4.3 Start Keycloak
```bash
cd /home/administrator/projects/keycloak
./deploy.sh

# Wait for Keycloak to be ready (can take 2-3 minutes)
echo "Waiting for Keycloak to start..."
sleep 30
docker logs keycloak --tail 20
```

### 4.4 Test Keycloak Login
```bash
# Test if Keycloak is responding
curl -I https://keycloak.ai-servicers.com 2>&1 | head -5

# Try to access admin console
echo "✓ Try logging into Keycloak admin: https://keycloak.ai-servicers.com"
echo "  (You may need to wait 1-2 more minutes if it's still starting)"
```

---

## Step 5: Restart Application Services (20 minutes)

### 5.1 Restart Infrastructure Services
```bash
# NGINX (static content)
cd /home/administrator/projects/nginx && ./deploy.sh

# Portainer (Docker management)
cd /home/administrator/projects/portainer && ./deploy.sh

# Database UIs
cd /home/administrator/projects/postgres && ./deploy-pgadmin-sso.sh
cd /home/administrator/projects/redis && ./deploy-redis-commander.sh
cd /home/administrator/projects/mongodb && ./deploy-mongo-express.sh
```

### 5.2 Restart User-Facing Services
```bash
# Dashboards
cd /home/administrator/projects/dashy && ./deploy.sh
cd /home/administrator/projects/dozzle && ./deploy.sh

# Collaboration
cd /home/administrator/projects/nextcloud && ./deploy.sh
cd /home/administrator/projects/guacamole && ./deploy.sh

# AI Tools
cd /home/administrator/projects/open-webui && ./deploy.sh
cd /home/administrator/projects/n8n && ./deploy.sh

# Context Management
cd /home/administrator/projects/alist && ./deploy.sh
cd /home/administrator/projects/obsidian && ./deploy.sh
cd /home/administrator/projects/matrix && ./deploy.sh

# Security
cd /home/administrator/projects/bitwarden && ./deploy.sh

# Development
cd /home/administrator/projects/gitlab && ./deploy.sh
cd /home/administrator/projects/playwright && ./deploy.sh
cd /home/administrator/projects/drawio && ./deploy.sh
```

### 5.3 Restart Monitoring
```bash
cd /home/administrator/projects/grafana && ./deploy.sh
cd /home/administrator/projects/loki && ./deploy.sh
cd /home/administrator/projects/netdata && ./deploy.sh
```

### 5.4 Restart Utility Services
```bash
cd /home/administrator/projects/microbin && ./deploy.sh
cd /home/administrator/projects/stirling-pdf && ./deploy.sh
```

---

## Step 6: Verification (5 minutes)

### 6.1 Check All Services Started
```bash
# Count running containers
echo "Total running containers: $(docker ps | wc -l)"

# Check for any exited/failed containers
echo ""
echo "Failed containers:"
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}"
```

### 6.2 Verify IP Range Compliance
```bash
# List all IPs on traefik-net
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | sort -t. -k4 -n > /tmp/traefik-net-after.txt

# Display the list
cat /tmp/traefik-net-after.txt

# Check for any IPs in the reserved range (should only be static assignments)
echo ""
echo "IPs in reserved range (172.25.0.2-172.25.0.127):"
cat /tmp/traefik-net-after.txt | awk -F'[. /]' '$2==25 && $3==0 && $4<128'

echo ""
echo "IPs in automatic range (172.25.0.128+):"
cat /tmp/traefik-net-after.txt | awk -F'[. /]' '$2==25 && $3==0 && $4>=128'
```

### 6.3 Test Key Services
```bash
# Test Traefik
curl -I https://traefik.ai-servicers.com:8083 2>&1 | grep HTTP

# Test Keycloak
curl -I https://keycloak.ai-servicers.com 2>&1 | grep HTTP

# Test Dashy
curl -I https://dashy.ai-servicers.com 2>&1 | grep HTTP

# Test Nextcloud
curl -I https://nextcloud.ai-servicers.com 2>&1 | grep HTTP

# Test Portainer
curl -I https://portainer.ai-servicers.com 2>&1 | grep HTTP
```

### 6.4 Compare Before/After
```bash
echo "Containers before network change:"
wc -l /tmp/traefik-net-before.txt

echo "Containers after network change:"
wc -l /tmp/traefik-net-after.txt

echo ""
echo "Differences:"
diff /tmp/traefik-net-before.txt /tmp/traefik-net-after.txt || echo "IP addresses changed (expected)"
```

---

## Step 7: Final Configuration

### 7.1 Update Documentation
```bash
# Document the new IP range policy
cat >> /home/administrator/projects/traefik/CLAUDE.md << 'EOF'

## IP Address Reservation (Updated 2025-10-31)

The traefik-net network now enforces IP range restrictions:
- **172.25.0.1**: Gateway
- **172.25.0.2-172.25.0.127**: Reserved for static IP assignments
  - 172.25.0.6: Traefik (critical)
  - 172.25.0.7: Traefik certs-dumper
  - Others available for future static assignments
- **172.25.0.128-172.25.0.255**: Automatic assignment pool (128 IPs)

This prevents containers from accidentally grabbing critical static IPs during boot.
EOF

echo "✓ Documentation updated"
```

### 7.2 Test Reboot Scenario
```bash
# Simulate a reboot by restarting Traefik
echo "Testing: Stopping and restarting Traefik to verify IP stays reserved..."
docker stop traefik
sleep 5

cd /home/administrator/projects/traefik
./deploy.sh

# Check if it got the right IP
docker network inspect traefik-net --format '{{range .Containers}}{{if eq .Name "traefik"}}{{.IPv4Address}}{{end}}{{end}}'
# Should output: 172.25.0.6/16
```

---

## Rollback Plan (If Something Goes Wrong)

### If services fail to start:
```bash
# Restore old network
docker network rm traefik-net
docker network create traefik-net --subnet=172.25.0.0/16 --gateway=172.25.0.1

# Restart critical services
cd /home/administrator/projects/traefik && ./deploy.sh
cd /home/administrator/projects/keycloak && ./deploy.sh

# Review logs
docker logs traefik --tail 50
docker logs keycloak --tail 50
```

### If you need the old network config:
```bash
cat /tmp/traefik-net-backup.json
```

---

## Success Criteria

✅ **Network recreated** with IP range restrictions
✅ **Traefik has IP 172.25.0.6** and is running
✅ **Keycloak is accessible** at https://keycloak.ai-servicers.com
✅ **Dashy is accessible** at https://dashy.ai-servicers.com
✅ **All services restarted** successfully
✅ **No containers have IPs** in range 172.25.0.51-172.25.0.127 (reserved but unused)
✅ **Auto-assigned IPs** are all 172.25.0.128 or higher

---

## Post-Fix Benefits

After this fix:
- ✅ Traefik's IP (172.25.0.6) cannot be claimed by other containers
- ✅ No more IP conflicts on reboot
- ✅ Clean separation between static and dynamic IPs
- ✅ Easier troubleshooting (static IPs are predictable)
- ✅ Room for 126 static IP assignments (172.25.0.2-172.25.0.127)
- ✅ Pool of 128 IPs for automatic assignment (172.25.0.128-172.25.0.255)

---

*Created: 2025-10-31*
*Estimated Duration: 30-60 minutes*
*Risk Level: Medium (requires stopping all services)*
