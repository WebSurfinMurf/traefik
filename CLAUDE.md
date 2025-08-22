# Claude AI Assistant Notes - Traefik

> **For overall environment context, see: `/home/administrator/projects/AINotes/AINotes.md`**

## Project Overview
Traefik is the primary reverse proxy and load balancer for all services, providing:
- HTTPS termination with Let's Encrypt certificates
- Automatic service discovery via Docker labels
- Certificate management and auto-renewal
- Multi-domain routing

## Recent Work & Changes
_This section is updated by Claude during each session_

### Session: 2025-08-22
- **MIGRATION COMPLETE**: Moved from websurfinmurf to administrator ownership
- Updated all paths to use administrator's directory structure
- Configured to use symlinked paths for secrets and data
- Properly configured on `traefik-proxy` network

### Session: 2025-08-19
- Migrated to administrator ownership at `/home/administrator/projects/traefik/`
- Updated deploy.sh to use `/home/administrator/projects/secrets/traefik.env`
- Certificate dump path now uses `/home/administrator/projects/data/traefik-certs/`

### Session: 2025-08-17
- Initial CLAUDE.md created
- **SECURITY FIX**: Moved certificates out of git repository
  - Certificates relocated to `/home/administrator/projects/data/traefik-certs/`
  - Added `certs` to .gitignore
  - Private keys should NEVER be in version control
- Added comprehensive .gitignore to prevent sensitive file commits
- acme.json removed from git history for security
- deploy.sh properly handles acme.json creation with 600 permissions

## Network Architecture
- **Network**: `traefik-proxy`
- **Connected Services**: All web-accessible services
- **Purpose**: Reverse proxy for external access
- **Note**: Database services use separate `postgres-net` network

## Important Files & Paths
- **Config**: `/home/administrator/projects/traefik/traefik.yml`
- **Certificates**: `/home/administrator/projects/traefik/acme.json` (chmod 600)
- **Cert Dumps**: `/home/administrator/projects/data/traefik-certs/`
- **Secrets**: `/home/administrator/projects/secrets/traefik.env`
- **Deploy Script**: `/home/administrator/projects/traefik/deploy.sh`

## Access Points
- **Dashboard**: https://traefik.ai-servicers.com:8083
- **HTTP**: Port 80 (redirects to HTTPS)
- **HTTPS**: Port 443
- **Metrics**: Port 9100

## Known Issues & TODOs
- None currently - service fully migrated and operational

## Important Notes
- **Owner**: administrator (UID 2000)
- **File ownership**: administrator:administrators
- **Certificates**: Stored securely with proper permissions
- **Security**: Private keys excluded from git via .gitignore
- **Network**: Part of traefik-proxy network only

## Dependencies
- Docker
- Let's Encrypt for SSL certificates
- Docker socket for service discovery

## Common Commands
```bash
# Deploy/restart Traefik
cd /home/administrator/projects/traefik
./deploy.sh

# Check Traefik logs
docker logs traefik --tail 50

# View running configuration
docker exec traefik traefik version

# Check certificate status
cat acme.json | jq '.Certificates[].domain'
```

## Backup Considerations
- **Critical**: acme.json (contains Let's Encrypt certificates)
- **Important**: traefik.yml, redirect.yml (configuration)
- **Location**: `/home/administrator/projects/backups/`

---
*Last Updated: 2025-08-22 by Claude*