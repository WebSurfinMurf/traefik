# Quick Start: Permanent Network Fix

## TL;DR

**Problem:** After reboot, containers grab Traefik's IP address randomly
**Solution:** Reserve IP ranges in the Docker network
**Time Required:** 30-60 minutes
**Downtime:** All services temporarily offline

---

## Two Options

### Option 1: Automated Script (Recommended)
```bash
cd /home/administrator/projects/traefik
./fix-network-automated.sh
```

**What it does:**
- ✅ Backs up current configuration
- ✅ Stops all services gracefully
- ✅ Recreates network with IP reservations
- ✅ Restarts all services automatically
- ✅ Verifies everything works

**Just run it and follow prompts.**

---

### Option 2: Manual Step-by-Step

If you prefer to do it manually or the script fails:

```bash
# Read the detailed guide
cat /home/administrator/projects/traefik/NETWORK-FIX-GUIDE.md

# Or open it with less for easier reading
less /home/administrator/projects/traefik/NETWORK-FIX-GUIDE.md
```

---

## What Will Change

### Before:
- Network: `172.25.0.0/16` (all IPs available)
- Containers grab any IP randomly
- ❌ Traefik's IP can be stolen on reboot

### After:
- **172.25.0.2-172.25.0.127** = Reserved for static IPs only
  - Traefik will always get 172.25.0.6
- **172.25.0.128-172.25.0.255** = Auto-assigned IPs only
  - 128 available IPs for other containers
- ✅ No more IP conflicts

---

## Pre-Flight Checklist

Before running, verify:
- [ ] You have 30-60 minutes available
- [ ] You can handle ~30 min of downtime
- [ ] All deploy scripts are working: `ls -lh /home/administrator/projects/*/deploy.sh`
- [ ] You have Keycloak admin credentials handy

---

## What Happens During the Fix

1. **Backup** current network state
2. **Stop** all containers (~5 min)
3. **Delete** old network
4. **Create** new network with IP restrictions
5. **Restart** services in correct order (~20 min):
   - Traefik first (gets 172.25.0.6)
   - Keycloak second
   - Everything else
6. **Verify** all services are running
7. **Test** key services (Traefik, Keycloak, Dashy)

---

## Run It Now

```bash
cd /home/administrator/projects/traefik
./fix-network-automated.sh
```

**Type 'yes' when prompted to proceed.**

---

## If Something Goes Wrong

### Rollback to old network:
```bash
docker network rm traefik-net
docker network create traefik-net --subnet=172.25.0.0/16 --gateway=172.25.0.1

# Restart Traefik
cd /home/administrator/projects/traefik && ./deploy.sh

# Restart Keycloak
cd /home/administrator/projects/keycloak && ./deploy.sh
```

### View backup:
```bash
ls -lh /tmp/traefik-net-fix-*/
cat /tmp/traefik-net-fix-*/network-config-backup.json
```

### Check what's running:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Manual restart if needed:
```bash
cd /home/administrator/projects/<service-name>
./deploy.sh
```

---

## After the Fix

Test these URLs in your browser:
- https://traefik.ai-servicers.com:8083 (Traefik Dashboard)
- https://keycloak.ai-servicers.com (Keycloak)
- https://dashy.ai-servicers.com (Dashy)
- https://portainer.ai-servicers.com (Portainer)

**All should work normally.**

---

## Future Reboots

After this fix:
- ✅ Traefik will **always** get IP 172.25.0.6
- ✅ Other containers get IPs from 172.25.0.128+
- ✅ No more IP conflicts
- ✅ Services start in any order without problems

---

## Questions?

- **Detailed Manual Guide:** `/home/administrator/projects/traefik/NETWORK-FIX-GUIDE.md`
- **Automated Script:** `/home/administrator/projects/traefik/fix-network-automated.sh`
- **IP Reservation Docs:** `/home/administrator/projects/traefik/IP-RESERVATION.md`

---

**Ready? Let's fix this permanently:**

```bash
cd /home/administrator/projects/traefik
./fix-network-automated.sh
```
