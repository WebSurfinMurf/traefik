# Traefik Reverse Proxy

**Version**: 3.4.3
**Status**: ✅ PRODUCTION
**Network**: traefik-net
**Domain**: ai-servicers.com

## Overview

Traefik is the primary reverse proxy and load balancer for the entire infrastructure, providing:
- HTTPS termination with Let's Encrypt certificates (Cloudflare DNS challenge)
- Automatic service discovery via Docker labels
- Certificate management and auto-renewal
- Multi-domain routing for HTTP/HTTPS and TCP services
- Centralized entry point for all external traffic

## Quick Start

```bash
# Deploy Traefik
cd /home/administrator/projects/traefik
./deploy.sh

# View logs
docker logs traefik -f

# Check health
docker exec traefik wget -qO- http://localhost:8083/api/version | jq

# View routers
docker exec traefik wget -qO- http://localhost:8083/api/http/routers | jq
```

## Architecture

### Services
- **traefik**: Main reverse proxy
- **traefik-certs-dumper**: Extracts certificates from acme.json for other services

### Networks
- **traefik-net**: Primary network for all web-facing services

### Entry Points
| Entry Point | Port | Purpose |
|-------------|------|---------|
| web | 80 | HTTP (redirects to HTTPS) |
| websecure | 443 | HTTPS with Let's Encrypt |
| traefik | 8083 | Dashboard & API |
| metrics | 9100 | Prometheus metrics |
| smtp | 25 | Incoming mail |
| smtps | 465 | SMTP over SSL |
| submission | 587 | Mail submission |
| imaps | 993 | IMAP over SSL |

## Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Service definitions |
| `deploy.sh` | Deployment script with validation |
| `traefik.yml` | Main Traefik configuration |
| `redirect.yml` | HTTP→HTTPS redirect rules |
| `acme.json` | Let's Encrypt certificates (chmod 600) |

## Secrets

**Location**: `$HOME/projects/secrets/traefik.env`

**Required Variables**:
```bash
TRAEFIK_CONTAINER_NAME=traefik
TRAEFIK_IMAGE=traefik:v3.4.3
TRAEFIK_NETWORK=traefik-net
TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80
TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443
TRAEFIK_ENTRYPOINTS_TRAEFIK_ADDRESS=:8083
TRAEFIK_ENTRYPOINTS_METRICS_ADDRESS=:9100
TRAEFIK_ENTRYPOINTS_SMTP_ADDRESS=:25
TRAEFIK_ENTRYPOINTS_SMTPS_ADDRESS=:465
TRAEFIK_ENTRYPOINTS_SUBMISSION_ADDRESS=:587
TRAEFIK_ENTRYPOINTS_IMAPS_ADDRESS=:993
TRAEFIK_ACME_FILE_PATH=/home/administrator/projects/traefik/acme.json
TRAEFIK_CERTS_DUMP_PATH=/home/administrator/projects/data/traefik-certs
CERTS_DUMPER_CONTAINER_NAME=traefik-certs-dumper
CERTS_DUMPER_IMAGE=ldez/traefik-certs-dumper:latest
CF_API_EMAIL=your-email@example.com
CF_API_KEY=your-cloudflare-api-key
```

## Certificate Management

### Let's Encrypt Configuration
- **Provider**: Cloudflare DNS challenge
- **Email**: websurfinmurf@gmail.com
- **Storage**: `/home/administrator/projects/traefik/acme.json`
- **Dumped Certs**: `/home/administrator/projects/data/traefik-certs/`

### Domains Covered
- `ai-servicers.com` (main domain)
- `*.ai-servicers.com` (wildcard)
- Individual service subdomains

### Certificate Operations
```bash
# Check certificates
cat acme.json | jq '.letsencrypt.Certificates[].domain'

# Force renewal
docker restart traefik

# View dumped certificates
ls -la /home/administrator/projects/data/traefik-certs/
```

## Service Integration

### Adding HTTP/HTTPS Service

Add these labels to your `docker-compose.yml`:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=traefik-net"
  - "traefik.http.routers.myapp.rule=Host(`myapp.ai-servicers.com`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls=true"
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

### Adding TCP Service

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.tcp.routers.myapp.rule=HostSNI(`*`)"
  - "traefik.tcp.routers.myapp.entrypoints=myport"
  - "traefik.tcp.routers.myapp.service=myapp"
  - "traefik.tcp.services.myapp.loadbalancer.server.port=8080"
```

## Access Points

- **Dashboard**: https://traefik.ai-servicers.com:8083
- **API**: http://localhost:8083/api/
- **Metrics**: http://localhost:9100/metrics

## Monitoring

### Health Check
```bash
docker exec traefik wget -qO- http://localhost:8083/api/version
```

### View Active Routers
```bash
# HTTP routers
docker exec traefik wget -qO- http://localhost:8083/api/http/routers | jq

# TCP routers
docker exec traefik wget -qO- http://localhost:8083/api/tcp/routers | jq

# Services
docker exec traefik wget -qO- http://localhost:8083/api/http/services | jq
```

### Check Logs
```bash
# Real-time logs
docker logs traefik -f

# Last 100 lines
docker logs traefik --tail 100

# Search for errors
docker logs traefik 2>&1 | grep -i error
```

## Troubleshooting

### Service Not Accessible

1. **Check container is on traefik-net**:
   ```bash
   docker inspect myapp | grep -A5 Networks
   ```

2. **Verify Traefik labels**:
   ```bash
   docker inspect myapp | grep -A20 Labels
   ```

3. **Check if router exists**:
   ```bash
   docker exec traefik wget -qO- http://localhost:8083/api/http/routers | jq '.[] | select(.name | contains("myapp"))'
   ```

4. **Review Traefik logs for the service**:
   ```bash
   docker logs traefik | grep myapp
   ```

### Certificate Issues

1. **Check acme.json permissions** (must be 600):
   ```bash
   ls -la acme.json
   ```

2. **Verify DNS challenge**:
   ```bash
   docker logs traefik | grep -i challenge
   ```

3. **Check Cloudflare API credentials** in `$HOME/projects/secrets/traefik.env`

4. **Manual certificate renewal**:
   ```bash
   docker restart traefik
   ```

### Port Already in Use

```bash
# Find what's using the port
sudo netstat -tlnp | grep :80

# Stop conflicting service
sudo systemctl stop apache2  # or nginx, etc.
```

## Deployment

### Standard Deployment
```bash
cd /home/administrator/projects/traefik
./deploy.sh
```

### Manual Deployment
```bash
cd /home/administrator/projects/traefik
docker compose up -d
```

### Rollback
```bash
cd /home/administrator/projects/traefik
docker compose down
# Restore previous configuration
docker compose up -d
```

## Backup

### Critical Files
- `acme.json` - Let's Encrypt certificates
- `traefik.yml` - Main configuration
- `redirect.yml` - Redirect rules
- `$HOME/projects/secrets/traefik.env` - Environment variables

### Backup Command
```bash
tar -czf traefik-backup-$(date +%Y%m%d).tar.gz \
  acme.json \
  traefik.yml \
  redirect.yml \
  $HOME/projects/secrets/traefik.env
```

## Security

- All HTTP traffic automatically redirects to HTTPS
- TLS 1.2+ enforced
- Let's Encrypt certificates auto-renewed
- Docker socket mounted read-only
- Dashboard accessible only via HTTPS
- Cloudflare DNS challenge (no port 80 exposure needed)

## Performance

- Handles 30+ HTTP routers
- TCP passthrough for mail services
- Prometheus metrics on port 9100
- Dashboard for real-time monitoring

## Related Documentation

- Network Standards: `/home/administrator/projects/AINotes/network.md`
- Network Topology: `/home/administrator/projects/AINotes/network-detail.md`
- Project Details: `/home/administrator/projects/traefik/CLAUDE.md`

---

**Last Updated**: 2025-09-30
**Standardized**: Phase 1 - Deployment Standardization
**Status**: ✅ Production Ready
