# Architecture

## Purpose
Reverse proxy fronting all `ai-servicers.com` public services (Tier-2) and `linuxserver.lan` internal services. Single ingress for HTTPS, TLS termination, automatic service discovery via Docker labels, automatic cert management via Let's Encrypt.

## Tech Stack
- [IMPLEMENTED] Traefik v3.6.16 (image pinned in `secrets/traefik.env`)
- [IMPLEMENTED] Docker Compose deployment
- [IMPLEMENTED] Let's Encrypt via DNS-01 (Cloudflare provider)
- [IMPLEMENTED] Plugin: `redirecterrors`
- [IMPLEMENTED] Sidecar: `ldez/traefik-certs-dumper:v2.8.3` (exports certs to disk for non-Traefik consumers)

## Components
- [IMPLEMENTED] `traefik` container — router, TLS terminator, ACME client. Static IP `172.25.0.6` on `traefik-net`. Mounts Docker socket RO.
- [IMPLEMENTED] `traefik-certs-dumper` container — watches `acme.json`, writes per-domain cert + key files to `projects/data/traefik-certs/<domain>/`.
- [IMPLEMENTED] File provider — `traefik.yml` (static config + entry points) and `redirect.yml` (file-defined routers: acme-challenge, homepage, livekit-debug, redirect-router).
- [IMPLEMENTED] Docker provider — discovers backend services via container labels (`traefik.enable=true`).

## Data Flow
Internet → Cloudflare DNS → residential external IP → ASUS router 192.168.1.13:443 → Traefik on host port 443 → backend container via `traefik-net` (or a cross-network bridge Traefik joins).

## Integrations
- Cloudflare DNS API — DNS-01 ACME challenge (TXT writes at `_acme-challenge.*`). Token in `secrets/traefik.env`, scope: Zone DNS Edit on `ai-servicers.com`.
- Let's Encrypt ACME v02 (production directory).
- Docker daemon (Unix socket, RO) — container/label discovery.
- `projects/ddns-updater` (separate project) — maintains apex/home/mail A records in Cloudflare via separate token. Required for *.ai-servicers.com to track residential IP after the 2026-05-23 architectural fix that decoupled resolution from `embracenow.asuscomm.com`.
- ASUS DDNS (`embracenow.asuscomm.com`) — still maintained by the router, but **no longer in any resolution path** for `ai-servicers.com`. Kept as break-glass fallback: if ddns-updater fails and external IP changes, manually flip apex back to `CNAME embracenow.asuscomm.com` to restore service.

## Patterns
- Label-driven service discovery (Docker provider) for HTTP services
- File-driven routes for cross-cutting static routes (redirects, ACME challenge fallback)
- TCP entry points + `HostSNI(\`*\`)` + TLS passthrough for mail (SMTP/SMTPS/Submission/IMAPS)
- Static container IP for Traefik (`172.25.0.6`) so other services can reference deterministically
