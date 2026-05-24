# Security

## Trust Boundaries
- **Public ingress:** Traefik on host ports 80/443 + mail TCP ports (25/465/587/993). Only externally-routed surface.
- **LAN-only ingress:** Same Traefik on `*.linuxserver.lan` rules (HTTP only, internal-only DNS).
- **Internal admin:** Traefik dashboard at `traefik.ai-servicers.com:8083` and `localhost:8083`. **No auth in front of dashboard currently.** Reachable from public (TLS only). Treat as elevated-trust.

## Auth Model
- Traefik itself terminates TLS but does NOT enforce app-level auth.
- Per-service auth via:
  - `keycloak-auth@file` ForwardAuth middleware (used by some services)
  - oauth2-proxy sidecar containers (e.g., `alist-auth-proxy`) sitting between Traefik and the backend
  - Native OIDC integration in apps (Grafana, GitLab, Nextcloud, …)
- Mail server: TLS passthrough — auth happens at the SMTP/IMAP layer.

## Secrets
- Location: `$HOME/projects/secrets/traefik.env`. Never in project directory; never committed.
- Load pattern: `set -a; source $ENV_FILE; set +a` (deploy.sh does this).
- Contents include: `CF_DNS_API_TOKEN` (Cloudflare API token, zone-scoped).
- `acme.json` (project directory) — contains private keys for every ACME-issued cert. **chmod 600 always.** Backup before destructive ops; never commit.

## Cloudflare Token Scope
- Token is scoped to **Zone DNS Edit on `ai-servicers.com` only** — least-privilege.
- Sufficient for: read records, write `_acme-challenge.*` TXT records, manage all DNS records in that zone.
- Insufficient for (intentionally): account-level operations, other zones.
- Rotation: regenerate in Cloudflare dashboard, update env file, redeploy.

## Required Patterns
- All public HTTPS services MUST use `tls.certresolver=letsencrypt`.
- `acme.json` mode 600 (deploy.sh enforces on every run).
- Sensitive endpoints (admin UIs, write APIs) MUST sit behind Keycloak ForwardAuth or oauth2-proxy.

## Forbidden Patterns
- No HTTP-only public exposure (always TLS for `*.ai-servicers.com`).
- No host-port publishing for backend containers (Traefik is the only ingress).
- No `--insecure` flags, no self-signed certs in production paths.
- No CF API tokens with broader scope than zone-DNS-edit unless specifically justified.

## Data Classification
- **Critical:** `acme.json` private keys; `CF_DNS_API_TOKEN`.
- **Sensitive:** Traefik logs (may contain auth headers, redirect URLs with tokens). Logs go to Promtail; access via Grafana (OAuth2-gated).
- **Public:** Cert public chain (dumped by certs-dumper for consumers); `traefik.yml`; `redirect.yml`; `docker-compose.yml`.
