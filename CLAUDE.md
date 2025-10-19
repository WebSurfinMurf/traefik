# Traefik Reverse Proxy - Complete Configuration Guide

> **For overall environment context, see: `/home/administrator/projects/AINotes/AINotes.md`**

## Project Overview
Traefik is the primary reverse proxy and load balancer for all services, providing:
- HTTPS termination with Let's Encrypt certificates (via Cloudflare DNS challenge)
- Automatic service discovery via Docker labels
- Certificate management and auto-renewal
- Multi-domain routing for both HTTP and TCP services
- Centralized entry point for all external traffic

## Network Architecture
- **Primary Network**: `traefik-net` (all web services connect here)
- **Host Ports Exposed**: 
  - 80 (HTTP → redirects to HTTPS)
  - 443 (HTTPS)
  - 25 (SMTP)
  - 465 (SMTPS)
  - 587 (Submission)
  - 993 (IMAPS)
  - 8083 (Traefik Dashboard)
  - 9100 (Metrics)

## Entry Points Configuration
```yaml
# HTTP/HTTPS Entry Points
web: ":80"           # HTTP (redirects to HTTPS)
websecure: ":443"    # HTTPS with Let's Encrypt
traefik: ":8083"     # Dashboard
metrics: ":9100"     # Prometheus metrics

# Mail Server TCP Entry Points  
smtp: ":25"          # Incoming mail
smtps: ":465"        # SMTP over SSL
submission: ":587"   # Mail submission
imaps: ":993"        # IMAP over SSL
```

## Service Routing Summary

### HTTP/HTTPS Services (via Traefik)

| Service | Domain | Port | Network | Auth |
|---------|--------|------|---------|------|
| **Keycloak** | keycloak.ai-servicers.com | 8080 | traefik-net, postgres-net | None |
| **Nextcloud** | nextcloud.ai-servicers.com | 80 | traefik-net, postgres-net, mailserver-net | Keycloak SSO |
| **Draw.io** | drawio.ai-servicers.com | 4180/8080 | traefik-net | OAuth2 Proxy |
| **PostfixAdmin** | postfixadmin.linuxserver.lan | 80 | traefik-net, postgres-net, mailserver-net | Internal only |
| **Main NGINX** | *.linuxserver.lan | 80 | traefik-net | Internal services |
| **Diagrams NGINX** | diagrams.nginx.ai-servicers.com | 80 | traefik-net | Public |

### TCP Services (Mail Server)

| Service | Port | Protocol | Container Port | Purpose |
|---------|------|----------|----------------|---------|
| SMTP | 25 | TCP | 25 | Incoming mail from internet |
| SMTPS | 465 | TCP | 465 | Secure SMTP (deprecated) |
| Submission | 587 | TCP | 587 | Client mail submission |
| IMAPS | 993 | TCP | 993 | Secure IMAP access |

### Direct Port Mappings (Bypassing Traefik)

| Service | Host Port | Container Port | Purpose |
|---------|-----------|----------------|---------|
| PostgreSQL | 5432 | 5432 | Database access |
| Keycloak | 8443 | 8443 | Admin console (backup) |
| PgAdmin | 8901 | 80 | Database management |
| Draw.io Auth | 8085 | 4180 | OAuth2 proxy direct |
| Open WebUI | 8000 | 8080 | AI interface |
| Portainer | 9000 | 9000 | Docker management |
| Rundeck | 4440 | 4440 | Job scheduler |
| ShellHub SSH | 2222 | 2222 | SSH gateway |

## Container Network Topology

### Networks and Their Services

**traefik-net** (External access network):
- traefik (router)
- keycloak (identity provider)
- nextcloud (file sharing)
- mailserver (email)
- postfixadmin (mail management)
- drawio + drawio-auth-proxy
- main-nginx, diagrams-nginx
- claude-code, claude-code-admin
- shellhub services
- open-webui

**postgres-net** (Database network):
- postgres (main database)
- keycloak-postgres (Keycloak DB)
- pgadmin (management)
- keycloak (app)
- postfixadmin (mail users)
- nextcloud (data)
- mailserver (user lookup)

**mailserver-net** (Email network):
- mailserver (SMTP/IMAP)
- postfixadmin (management)
- nextcloud (mail client)

## Traefik Label Configuration Examples

### HTTP Service (Nextcloud)
```bash
--label "traefik.enable=true"
--label "traefik.docker.network=traefik-net"
--label "traefik.http.routers.nextcloud.rule=Host(\`nextcloud.ai-servicers.com\`)"
--label "traefik.http.routers.nextcloud.entrypoints=websecure"
--label "traefik.http.routers.nextcloud.tls=true"
--label "traefik.http.routers.nextcloud.tls.certresolver=letsencrypt"
--label "traefik.http.services.nextcloud.loadbalancer.server.port=80"
```

### TCP Service (Mail Server)
```bash
--label "traefik.tcp.routers.mailserver-imaps.rule=HostSNI(\`*\`)"
--label "traefik.tcp.routers.mailserver-imaps.entrypoints=imaps"
--label "traefik.tcp.routers.mailserver-imaps.service=mailserver-imaps"
--label "traefik.tcp.services.mailserver-imaps.loadbalancer.server.port=993"
```

## Certificate Management
- **Provider**: Let's Encrypt via Cloudflare DNS challenge
- **Storage**: `/home/administrator/projects/traefik/acme.json` (chmod 600)
- **Dumped Certs**: `/home/administrator/projects/data/traefik-certs/`
- **Domains Covered**: 
  - ai-servicers.com (main)
  - *.ai-servicers.com (wildcard)
  - linuxserver.lan (internal)

## Important Files & Paths
- **Main Config**: `/home/administrator/projects/traefik/traefik.yml`
- **Redirect Rules**: `/home/administrator/projects/traefik/redirect.yml`
- **Deploy Script**: `/home/administrator/projects/traefik/deploy.sh`
- **Secrets**: `$HOME/projects/secrets/traefik.env`
- **Certificates**: `/home/administrator/projects/traefik/acme.json`
- **Cert Dumps**: `/home/administrator/projects/data/traefik-certs/`

## Access Points
- **Dashboard**: https://traefik.ai-servicers.com:8083
- **Metrics**: http://linuxserver.lan:9100/metrics

## Known Issues & Current Status

### Working Services
- ✅ Keycloak (HTTPS + internal HTTP)
- ✅ Nextcloud (HTTPS with SSO + Mail integration)
- ✅ Draw.io (HTTPS with OAuth2)
- ✅ PostgreSQL databases
- ✅ NGINX services (internal)
- ✅ Traefik dashboard
- ✅ Mail server (SMTP/IMAP/Submission via TCP routing)
- ✅ PostfixAdmin (internal access at postfixadmin.linuxserver.lan)

### Resolved Issues
- ✅ FIXED: Mail server TCP routing now working with TLS passthrough
- ✅ FIXED: Container connectivity via hosts file workaround for NAT reflection
- ✅ WORKING: Nextcloud can connect to mail server via mail.ai-servicers.com

### Router NAT Reflection Workaround
ASUS routers with Merlin firmware cause mail.ai-servicers.com to resolve to local IP (192.168.1.13).
Docker containers cannot reach host's local IP, so Nextcloud uses:
- External DNS servers (8.8.8.8)
- Hosts entry mapping mail.ai-servicers.com → 172.22.0.17 (Docker network IP)

## Common Commands
```bash
# Deploy/restart Traefik
cd /home/administrator/projects/traefik
./deploy.sh

# Check Traefik logs
docker logs traefik --tail 50 -f

# View running configuration
docker exec traefik traefik version

# Check certificate status
cat acme.json | jq '.letsencrypt.Certificates[].domain'

# Test TCP routing
nc -zv mail.ai-servicers.com 993

# Check HTTP routing
curl -I https://nextcloud.ai-servicers.com

# View all routes
curl -s http://localhost:8083/api/http/routers | jq
curl -s http://localhost:8083/api/tcp/routers | jq
```

## Troubleshooting

### Service Not Accessible
1. Check container is running: `docker ps | grep <service>`
2. Verify labels: `docker inspect <container> | grep -A20 Labels`
3. Check networks: `docker inspect <container> | grep -A5 Networks`
4. Review Traefik logs: `docker logs traefik | grep <service>`

### TCP Services Not Working
1. Verify entrypoint exists in traefik.yml
2. Check port is exposed: `netstat -tlnp | grep <port>`
3. Test locally: `docker exec traefik nc -zv <container> <port>`
4. Check firewall: `sudo iptables -L -n | grep <port>`

### Certificate Issues
1. Check acme.json permissions: `ls -la acme.json` (should be 600)
2. Verify DNS challenge: `docker logs traefik | grep challenge`
3. Check Cloudflare API token in environment
4. Manual renewal: `docker restart traefik`

## Security Considerations
- All external traffic goes through Traefik
- HTTPS enforced for all public services
- Internal services use `.linuxserver.lan` domain
- OAuth2/Keycloak protection for sensitive services
- TCP services use TLS where supported
- Certificates auto-renewed before expiry

## Backup Requirements
- **Critical**: acme.json (certificates)
- **Important**: traefik.yml, redirect.yml
- **Nice to have**: Container labels (in deploy scripts)

---
*Last Updated: 2025-08-24 by Claude*
*Status: ✅ FULLY OPERATIONAL - All services working including mail*