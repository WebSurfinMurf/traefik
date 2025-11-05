# Working Configuration Backup - 2025-11-04

## What This Is
Backup of WORKING Traefik certificate configuration before attempting to add *.nginx.ai-servicers.com wildcard.

## Current State (Working)
- Certificate: *.ai-servicers.com wildcard (Let's Encrypt)
- acme.json permissions: 600
- All HTTPS working with valid Let's Encrypt certificate

## What's Backed Up
1. **acme.json** - Let's Encrypt certificate storage (CRITICAL)
2. nginx-deploy.sh - Nginx Traefik routing labels (for reference)
3. configs/ - Nginx virtual hosts (for reference)
4. sites/ - Static content (for reference)

## Quick Restore If Rate Limited
```bash
docker stop traefik
cp /home/administrator/projects/traefik/backups/working-20251104-222951/acme.json /home/administrator/projects/traefik/acme.json
chmod 600 /home/administrator/projects/traefik/acme.json
docker start traefik
```

## Certificate Details
Subject: ai-servicers.com
SANs: 
  - *.ai-servicers.com (wildcard for single-level subdomains)
  - ai-servicers.com (base domain)
Issuer: Let's Encrypt (R13)

---
Created: 2025-11-04 22:29:51
Moved to traefik/backups: 2025-11-04 22:33
