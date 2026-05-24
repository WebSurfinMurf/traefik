# Conventions

## Networking
- All HTTP services join `traefik-net` (subnet `172.25.0.0/16`).
- Traefik gets static IP `172.25.0.6`; `deploy.sh` includes IP-conflict reconcile logic.
- Backend services should expose only the listener port; do NOT publish host ports unless explicitly required.
- LAN-only services use `*.linuxserver.lan` on `web` entrypoint (no TLS).
- Public services use `*.ai-servicers.com` on `websecure` entrypoint with `tls.certresolver=letsencrypt`.

## Label Style
- Router names: `<service>` for the primary HTTPS router; suffix for variants (`<service>-internal` for LAN, `<service>-redirect`, `<service>-api`, etc.).
- Always set `traefik.docker.network=traefik-net` even if the container is on only one network — explicit beats implicit.

## File Structure
- `traefik.yml` — static config (entry points, providers, ACME resolver, plugins, log/metrics)
- `redirect.yml` — file-provider dynamic config (file-defined routers/middlewares)
- `docker-compose.yml` — Traefik + certs-dumper services
- `deploy.sh` — single entry point for build/deploy. Run from project dir.
- `acme.json` — ACME state; chmod 600 always; backed up before destructive ops
- `secrets/traefik.env` (at `$HOME/projects/secrets/traefik.env`) — image tag, CF token, entry-point overrides, ACME paths

## Image Pinning
- `TRAEFIK_IMAGE` in `secrets/traefik.env` pins the exact image tag.
- Upgrade flow: edit env, run `./deploy.sh`. Do not change in `docker-compose.yml` directly.

## Deploy Discipline
- Never `docker run` Traefik manually — always `./deploy.sh`.
- `deploy.sh` runs `docker compose up -d --remove-orphans`. Containers not in this compose file but labeled with this project will be removed — be aware when adding sidecars.
- `deploy.sh` validates network exists, secrets present, acme.json present + 600, compose syntax valid before applying changes.

## Logging
- Auto-discovered by Promtail at `linuxserver.lan` infrastructure level. No per-service config needed.
- Traefik log level: INFO by default. Bump to DEBUG only for diagnosis; revert after.

## Restart vs Reload
- Traefik hot-reloads file-provider config (traefik.yml, redirect.yml) on file change.
- Container restart required for: image change, static config change (loglevel, entrypoints, plugins), env var change.
- Docker provider hot-discovers containers; no restart needed when adding/removing backend services.

## Cross-Project References
- Master infrastructure index: `projects/CLAUDE.md`
- Network conventions: `projects/AINotes/network.md`
- Secrets layout: `$HOME/projects/secrets/{service}.env`
