# Traefik IP Address Reservation

## Problem
After power loss/reboots, Docker containers may start in random order. If nginx or another container starts before Traefik, it can grab Traefik's static IP address (172.25.0.6), preventing Traefik from starting.

## Current Solution (Implemented)
**Auto-Detection in Deploy Script** - The `/home/administrator/projects/traefik/deploy.sh` script now:
1. Checks if IP 172.25.0.6 is already in use
2. If occupied by another container, disconnects that container from traefik-net
3. Reconnects the container with an automatic IP
4. Proceeds with Traefik deployment

**Pros:**
- ✅ No downtime required
- ✅ Automatically fixes conflicts on every deploy
- ✅ No manual intervention needed

**Cons:**
- ⚠️ Relies on deploy script being run
- ⚠️ Container that gets bumped off the IP will temporarily lose connectivity

## Alternative Solution (More Robust)
**Network IP Range Restriction** - Reserve IPs 172.25.0.2-172.25.0.127 for static assignments.

### How It Works
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
```

This configuration:
- Reserves 172.25.0.2-172.25.0.127 for static IPs
- Only assigns 172.25.0.128-172.25.0.255 automatically (128 IPs)
- Marks key IPs as reserved via aux-addresses

**Pros:**
- ✅ Permanent solution - prevents conflicts at network level
- ✅ No container can accidentally grab reserved IPs
- ✅ Clean separation between static and dynamic IPs

**Cons:**
- ❌ Requires stopping ALL containers on traefik-net
- ❌ Network must be deleted and recreated
- ❌ All services must be restarted in correct order
- ❌ ~30-60 minutes of downtime

### Implementation Scripts
Automated script available at: `/home/administrator/projects/traefik/fix-network-automated.sh`

**To implement the permanent fix:**
```bash
# Quick start (automated)
cd /home/administrator/projects/traefik
./fix-network-automated.sh

# Or follow manual guide
less /home/administrator/projects/traefik/NETWORK-FIX-GUIDE.md
```

## Reserved IP Assignments (After Fix)
Based on new network configuration:

| IP Range | Purpose | Notes |
|----------|---------|-------|
| 172.25.0.1 | Gateway | Network gateway |
| 172.25.0.6 | **traefik** | Critical - reverse proxy for all services |
| 172.25.0.7 | traefik-certs-dumper | Certificate extraction |
| 172.25.0.2-172.25.0.127 | Reserved | For static IP assignments |
| 172.25.0.128-172.25.0.255 | Auto-assigned | Dynamic pool (128 IPs) |

## Recommendation
- **Current approach** (auto-fix in deploy script) is sufficient for normal operations
- **Network restriction** should be implemented during next planned maintenance window
- Document any new static IP assignments in this file

## Testing the Current Fix
```bash
# Simulate the conflict
docker network disconnect traefik-net nginx
docker network connect --ip 172.25.0.6 traefik-net nginx

# Run deploy script - should auto-fix
cd /home/administrator/projects/traefik
./deploy.sh

# Verify Traefik got its IP back
docker network inspect traefik-net --format '{{range .Containers}}{{.Name}} - {{.IPv4Address}}{{"\n"}}{{end}}' | grep traefik
```

---
*Created: 2025-10-31*
*Status: Auto-fix implemented in deploy.sh*
