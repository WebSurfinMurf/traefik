# Requirements

## Functional
- Route all public HTTPS traffic for `ai-servicers.com` to the correct backend container.
- Route LAN-only HTTP traffic for `*.linuxserver.lan` to internal services.
- Terminate TLS with valid Let's Encrypt certificates; auto-renew before expiry.
- Pass mail TCP traffic (SMTP/SMTPS/Submission/IMAPS) through to mailserver with SNI-only routing (TLS handled by mailserver).
- Auto-discover new services via Docker labels — no Traefik config edit needed to onboard a labeled container.
- Provide a Prometheus metrics endpoint for observability.
- Provide an admin dashboard for inspection of routers/middlewares/services.

## Non-Functional
- **Availability:** Outage = total public service outage. Reload static config without dropping connections where possible.
- **Cert renewal latency:** Cert expiry must NOT cause an outage. Renewal triggers at 30 days before expiry; failures must be visible in logs.
- **Onboarding latency:** New labeled container should be route-discoverable within ~10s.
- **Blast radius awareness:** Image upgrades and config changes must be reversible in <60s.

## User Workflows Supported
- Browser user hits `https://<service>.ai-servicers.com` → TLS termination → SSO challenge (if applicable) → backend response.
- Admin on LAN hits `http://<service>.linuxserver.lan` → backend (no TLS, no SSO).
- Mail client connects to `mail.ai-servicers.com:993` (IMAPS) or `:587` (submission) → TLS passthrough → mailserver auth.
- Operator deploys a new service: adds labels, `docker compose up -d` on that service, route appears in Traefik automatically.

## Out of Scope
- Application-level auth (per-service, see `security.md`).
- Application-level rate limiting (per-service).
- DDoS protection (handled at Cloudflare layer).
- Cert distribution to non-containerized consumers (certs-dumper handles this via filesystem export).
