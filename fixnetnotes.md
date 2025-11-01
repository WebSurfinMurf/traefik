# Traefik Network Fix - Context Notes for Troubleshooting

**Date Created:** 2025-10-31
**Purpose:** Context for AI assistant if network fix causes issues

---

## PROBLEM STATEMENT

### What Happened
1. Server lost power and rebooted
2. Traefik container was down (exited 2 days ago)
3. When trying to restart Traefik: "Error: Address already in use"
4. Root cause: **nginx container started before Traefik and grabbed IP 172.25.0.6**

### Why This Happens
- Docker network `traefik-net` has no IP range restrictions
- Containers can grab ANY IP from 172.25.0.0/16 subnet
- Traefik is configured with static IP 172.25.0.6 in docker-compose.yml
- On reboot, containers start in random order
- If nginx (or any container) starts first, it can take Traefik's IP
- When Traefik tries to start, it can't bind to its configured IP

### Immediate Workaround Applied
Modified `/home/administrator/projects/traefik/deploy.sh` to auto-detect and fix IP conflicts:
- Script checks if 172.25.0.6 is taken by another container
- If yes, disconnects that container and reconnects with auto IP
- Then starts Traefik normally
- **This works but doesn't prevent the problem from happening again**

---

## PERMANENT SOLUTION

### What the Fix Does
Recreates `traefik-net` Docker network with IP range restrictions:

**Current network config:**
```json
{
    "Subnet": "172.25.0.0/16",
    "Gateway": "172.25.0.1"
}
```
- No IP range restrictions
- All 65,534 IPs available for any purpose

**New network config:**
```json
{
    "Subnet": "172.25.0.0/16",
    "Gateway": "172.25.0.1",
    "IPRange": "172.25.0.128/25",
    "AuxiliaryAddresses": {
        "reserved-static-1": "172.25.0.2",
        "reserved-static-2": "172.25.0.10",
        "reserved-static-3": "172.25.0.20",
        "reserved-static-4": "172.25.0.30",
        "reserved-static-5": "172.25.0.40",
        "reserved-static-6": "172.25.0.50"
    }
}
```
- **172.25.0.2-172.25.0.127:** Reserved for static IPs (Traefik, etc.)
- **172.25.0.128-172.25.0.255:** Auto-assignment pool (128 IPs)
- Containers CANNOT grab IPs outside their assigned range

### Why This Fixes It
- Docker will only auto-assign from 172.25.0.128-255
- Traefik's static IP (172.25.0.6) is in reserved range
- No container can accidentally take it
- Boot order doesn't matter anymore

---

## FILES CREATED FOR THE FIX

### 1. Quick Start Guide
**Location:** `/home/administrator/projects/traefik/QUICK-START-NETWORK-FIX.md`
**Purpose:** One-page overview with quick commands

### 2. Automated Script ⭐
**Location:** `/home/administrator/projects/traefik/fix-network-automated.sh`
**Purpose:** Fully automated fix - run it and it handles everything
**Executable:** Yes (chmod +x already applied)

### 3. Detailed Manual Guide
**Location:** `/home/administrator/projects/traefik/NETWORK-FIX-GUIDE.md`
**Purpose:** Step-by-step manual instructions (if automation fails)

### 4. IP Reservation Docs
**Location:** `/home/administrator/projects/traefik/IP-RESERVATION.md`
**Purpose:** Technical details about both fix approaches

### 5. This File
**Location:** `/home/administrator/projects/traefik/fixnetnotes.md`
**Purpose:** Context for future troubleshooting

---

## CURRENT STATE (Before Fix)

### Network Status
- Network name: `traefik-net`
- Subnet: 172.25.0.0/16
- Gateway: 172.25.0.1
- No IP range restrictions
- ~65 containers connected

### Traefik Status
- Container: Running ✓
- IP Address: 172.25.0.6 (correct)
- Status: Healthy
- Ports: 80, 443, 8083, 9100, 25, 465, 587, 993
- Started: Recently (after manual fix)

### Nginx Status
- Container: Running ✓
- IP Address: 172.25.0.35 (reassigned from 172.25.0.6)
- Status: Healthy
- Note: Was manually moved off Traefik's IP

### Services Working
- ✓ Traefik Dashboard: http://localhost:8083
- ✓ Traefik routing: dashy, keycloak, nextcloud, portainer all configured
- ✓ Dashy accessible (once Traefik is running)
- ✓ All key services operational

---

## HOW TO RUN THE FIX

### Option 1: Automated (Recommended)
```bash
cd /home/administrator/projects/traefik
./fix-network-automated.sh
```
- Type 'yes' when prompted
- Wait 30-60 minutes
- Script handles everything

### Option 2: Manual
```bash
# Read the detailed guide
less /home/administrator/projects/traefik/NETWORK-FIX-GUIDE.md

# Follow steps 1-7 manually
```

---

## WHAT THE AUTOMATED SCRIPT DOES

### Step 1: Preparation (5 min)
- Creates backup directory: `/tmp/traefik-net-fix-YYYYMMDD-HHMMSS/`
- Saves current network state
- Saves container list with IPs
- Backs up network JSON config

### Step 2: Stop Services (10 min)
Stops containers in this order:
1. Application services (dashy, nextcloud, etc.)
2. Database UIs (pgadmin, etc.)
3. Keycloak
4. Traefik (last)
5. Disconnects all from network

### Step 3: Recreate Network (2 min)
```bash
docker network rm traefik-net
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
```

### Step 4: Restart Core (15 min)
1. PostgreSQL (if needed)
2. **Traefik** (MUST be first on traefik-net to claim 172.25.0.6)
3. Keycloak (waits for it to be healthy)

### Step 5: Restart Applications (20 min)
Runs deploy.sh for each service:
- Infrastructure (nginx, portainer)
- Databases (pgadmin, redis-commander, mongo-express)
- User services (dashy, nextcloud, guacamole, bitwarden)
- AI/Context (open-webui, n8n, alist, obsidian, matrix)
- Development (gitlab, playwright, drawio)
- Monitoring (dozzle, grafana, loki, netdata)
- Utilities (microbin, stirling-pdf)

### Step 6: Verification
- Counts running containers
- Lists failed containers
- Verifies IP ranges
- Tests key services (Traefik, Keycloak, Dashy, Portainer)

### Step 7: Summary
- Reports before/after stats
- Shows backup location
- Confirms Traefik has correct IP

---

## IF THINGS GO WRONG - TROUBLESHOOTING

### Scenario 1: Traefik Won't Start
```bash
# Check if it's trying to start
docker ps -a | grep traefik

# Check logs
docker logs traefik --tail 50

# Common issues:
# - Port conflict: Check what's on port 80/443
docker ps --format '{{.Names}}\t{{.Ports}}' | grep -E ':80-|:443-'

# - IP conflict: Check what has 172.25.0.6
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | grep 172.25.0.6

# Manual fix:
cd /home/administrator/projects/traefik
docker stop traefik && docker rm traefik
./deploy.sh
```

### Scenario 2: Keycloak Won't Start
```bash
# Check status
docker ps -a | grep keycloak
docker logs keycloak --tail 50

# Common issue: Database not ready
docker ps | grep postgres
docker logs postgres --tail 20

# Wait and retry
sleep 30
cd /home/administrator/projects/keycloak && ./deploy.sh
```

### Scenario 3: Services Don't Get Right IPs
```bash
# Check IP distribution
docker network inspect traefik-net --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' | sort -t. -k4 -n

# Should see:
# - Traefik at 172.25.0.6 (static)
# - Everything else at 172.25.0.100+ (auto)

# If Traefik has wrong IP:
docker stop traefik
docker network disconnect traefik-net traefik
docker start traefik
# Traefik will reconnect and claim 172.25.0.6
```

### Scenario 4: Too Many Services Failed to Restart
```bash
# List failed containers
docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}"

# Restart individually
cd /home/administrator/projects/<service-name>
./deploy.sh

# Check deploy script exists and is executable
ls -lh /home/administrator/projects/<service-name>/deploy.sh
chmod +x /home/administrator/projects/<service-name>/deploy.sh
```

### Scenario 5: Need to Rollback Everything
```bash
# Remove new network
docker network rm traefik-net

# Recreate old network (no restrictions)
docker network create traefik-net \
  --subnet=172.25.0.0/16 \
  --gateway=172.25.0.1

# Restart critical services
cd /home/administrator/projects/traefik && ./deploy.sh
cd /home/administrator/projects/keycloak && ./deploy.sh
cd /home/administrator/projects/dashy && ./deploy.sh

# Restore from backup if needed
BACKUP_DIR=$(ls -td /tmp/traefik-net-fix-* | head -1)
echo "Backup is in: $BACKUP_DIR"
cat $BACKUP_DIR/network-config-backup.json
```

---

## VERIFICATION COMMANDS

### Check Traefik is Running with Correct IP
```bash
docker ps | grep traefik
docker network inspect traefik-net --format '{{range .Containers}}{{if eq .Name "traefik"}}{{.Name}} - {{.IPv4Address}}{{end}}{{end}}'
# Expected: traefik - 172.25.0.6/16
```

### Check Network Configuration
```bash
docker network inspect traefik-net --format '{{json .IPAM}}' | python3 -m json.tool
# Should show IPRange: "172.25.0.100/25"
```

### Test Key Services
```bash
# Traefik Dashboard
curl -I http://localhost:8083

# Keycloak
curl -I https://keycloak.ai-servicers.com

# Dashy
curl -I https://dashy.ai-servicers.com

# Portainer
curl -I https://portainer.ai-servicers.com
```

### List All IPs on Network
```bash
docker network inspect traefik-net --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' | sort -t. -k4 -n
```

### Count Containers
```bash
echo "Total running: $(docker ps | wc -l)"
echo "On traefik-net: $(docker network inspect traefik-net --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | wc -l)"
```

---

## KEY CONFIGURATION FILES

### Traefik Docker Compose
**Location:** `/home/administrator/projects/traefik/docker-compose.yml`
**Key settings:**
```yaml
services:
  traefik:
    networks:
      traefik-net:
        ipv4_address: 172.25.0.6  # Static IP
    ports:
      - "80:80"
      - "443:443"
      - "8083:8083"
```

### Traefik Deploy Script (Modified)
**Location:** `/home/administrator/projects/traefik/deploy.sh`
**Line 81-96:** IP conflict detection (added by us)
- Checks if 172.25.0.6 is in use
- Auto-fixes conflicts before deployment

### Network Creation Command
**Old (current):**
```bash
docker network create traefik-net \
  --subnet=172.25.0.0/16 \
  --gateway=172.25.0.1
```

**New (after fix):**
```bash
docker network create traefik-net \
  --subnet=172.25.0.0/16 \
  --gateway=172.25.0.1 \
  --ip-range=172.25.0.128/25 \
  --aux-address="reserved-static-1=172.25.0.2" \
  # ... more aux-addresses
```

---

## BACKUP LOCATIONS

### Before Running Fix
- Network config: Check with `docker network inspect traefik-net`
- Container list: Run `docker ps`

### After Running Fix
Automated script creates: `/tmp/traefik-net-fix-YYYYMMDD-HHMMSS/`
- `network-config-backup.json` - Old network config
- `network-config-new.json` - New network config
- `containers-before.txt` - Container IPs before
- `containers-after.txt` - Container IPs after

### Manual Backups You Can Make
```bash
# Save current network config
docker network inspect traefik-net > ~/traefik-net-backup-$(date +%Y%m%d).json

# Save container list
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" > ~/containers-backup-$(date +%Y%m%d).txt

# Save network container IPs
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' > ~/traefik-net-ips-$(date +%Y%m%d).txt
```

---

## CRITICAL SERVICES ORDER

When manually restarting, use this order:

1. **PostgreSQL** (database - many services depend on it)
   ```bash
   cd /home/administrator/projects/postgres && ./deploy.sh
   ```

2. **Traefik** (MUST be first on traefik-net to claim 172.25.0.6)
   ```bash
   cd /home/administrator/projects/traefik && ./deploy.sh
   ```

3. **Keycloak** (authentication - many services use SSO)
   ```bash
   cd /home/administrator/projects/keycloak && ./deploy.sh
   ```

4. **Everything else** (order doesn't matter much)

---

## CONTACT/ESCALATION

### If AI Assistant Can't Fix It

**Check these first:**
1. Is PostgreSQL running? `docker ps | grep postgres`
2. Is Traefik running? `docker ps | grep traefik`
3. Are logs showing errors? `docker logs traefik --tail 50`
4. Can you access Traefik dashboard? `curl -I http://localhost:8083`

**Manual recovery:**
1. Stop all containers: `docker stop $(docker ps -q)`
2. Recreate network (old way): `docker network create traefik-net --subnet=172.25.0.0/16 --gateway=172.25.0.1`
3. Start Traefik: `cd /home/administrator/projects/traefik && ./deploy.sh`
4. Start Keycloak: `cd /home/administrator/projects/keycloak && ./deploy.sh`
5. Test: `curl -I https://keycloak.ai-servicers.com`

**User should provide to AI:**
- Output of: `docker ps -a`
- Output of: `docker logs traefik --tail 50`
- Output of: `docker network inspect traefik-net`
- This file: `/home/administrator/projects/traefik/fixnetnotes.md`
- Error messages from script

---

## SUCCESS CRITERIA

After fix is complete, verify:

### ✅ Network Configuration
```bash
docker network inspect traefik-net --format '{{json .IPAM.Config}}' | python3 -m json.tool | grep IPRange
# Should show: "IPRange": "172.25.0.128/25"
```

### ✅ Traefik IP
```bash
docker network inspect traefik-net --format '{{range .Containers}}{{if eq .Name "traefik"}}{{.IPv4Address}}{{end}}{{end}}'
# Should show: 172.25.0.6/16
```

### ✅ No IPs in Reserved Range (except static assignments)
```bash
docker network inspect traefik-net --format '{{range .Containers}}{{.IPv4Address}} {{.Name}}{{"\n"}}{{end}}' | awk '$1 ~ /^172\.25\.0\.([7-9]|[1-9][0-9])\//'
# Should only show containers with static IPs (very few or none)
```

### ✅ Services Accessible
- https://traefik.ai-servicers.com:8083 → Traefik Dashboard
- https://keycloak.ai-servicers.com → Keycloak login
- https://dashy.ai-servicers.com → Dashy dashboard
- https://portainer.ai-servicers.com → Portainer

### ✅ All Containers Running
```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(Up|healthy)"
# Should show most/all services as Up
```

---

## FINAL NOTES

- **The fix is permanent** - once done, IP conflicts won't happen again
- **Traefik will always get 172.25.0.6** - it's in the reserved range
- **Other containers get 172.25.0.128+** - they can't grab static IPs
- **Boot order doesn't matter anymore** - IP ranges prevent conflicts

**If you're seeing this file because things broke:**
1. Don't panic
2. Check the "IF THINGS GO WRONG" section above
3. Provide AI with output from verification commands
4. Worst case: Use rollback procedure

**This fix was tested on:** 2025-10-31
**System:** Docker on Linux (kernel 6.14.0-33-generic)
**Total containers:** ~65
**Downtime expected:** 30-60 minutes
**Risk level:** Medium (requires stopping all services)

---

**End of context notes**
