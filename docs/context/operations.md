# Operations

## Prerequisites
- `traefik-net` Docker network exists (created by `projects/infrastructure/setup-networks.sh`)
- `$HOME/projects/secrets/traefik.env` exists with `CF_DNS_API_TOKEN` and `TRAEFIK_IMAGE` set
- `projects/traefik/acme.json` exists, chmod 600
- `projects/data/traefik-certs/` directory writable for certs-dumper sidecar
- Cloudflare zone `ai-servicers.com` has the apex+wildcard+home+mail records described in `interfaces.md` (Cloudflare zone shape)
- `projects/ddns-updater` is running and maintaining `home.ai-servicers.com` A — this is the wildcard CNAME target; if stale, `*.ai-servicers.com` will not resolve correctly after an external IP change

## Environment Variables
| Name | Required | Description |
|---|---|---|
| `TRAEFIK_IMAGE` | yes | e.g. `traefik:v3.6.16`. Drives container image. |
| `TRAEFIK_CONTAINER_NAME` | no | Default `traefik` |
| `CF_DNS_API_TOKEN` | yes | Cloudflare API token, scope `Zone:DNS:Edit` on `ai-servicers.com` |
| `TRAEFIK_ACME_FILE_PATH` | yes | Absolute path to `acme.json` (default `./acme.json`) |
| `TRAEFIK_CERTS_DUMP_PATH` | yes | Where certs-dumper writes per-domain cert files |
| `TRAEFIK_ENTRYPOINTS_*_ADDRESS` | no | Override entry-point bindings (default values in compose) |
| `CERTS_DUMPER_IMAGE` | no | Default `ldez/traefik-certs-dumper:v2.8.3` |

## Build & Run
```
cd /home/administrator/projects/traefik
./deploy.sh
```

`deploy.sh` is idempotent. Brings up `traefik` and `traefik-certs-dumper`, removes orphans, waits for health.

## Upgrade Path
1. Edit `TRAEFIK_IMAGE` in `secrets/traefik.env`.
2. `./deploy.sh`.
3. Verify: `docker exec traefik traefik version`; `curl -s http://localhost:8083/api/version`; spot-check 2-3 public hosts respond.

## Health Checks
- `docker exec traefik wget -qO- http://localhost:8083/api/version | grep Version` — used by deploy.sh
- `curl -s http://localhost:8083/api/http/routers | jq 'length'` — expect 70+ after the docker provider loads
- `docker logs traefik --since 5m | grep -iE 'error|warn'` — should be empty (ignoring known ACME issues during the migration window)

## Rollback
- Image: revert `TRAEFIK_IMAGE` in `secrets/traefik.env`, `./deploy.sh`. ~10s outage.
- `acme.json`: `docker stop traefik && cp acme.json.bak-<ts> acme.json && docker start traefik`
- Removed sidecar (orphaned by `--remove-orphans`): redeploy from its own compose context

## Common Commands
```
# logs
docker logs traefik --tail 100 -f

# version
docker exec traefik traefik version

# certs in acme.json
jq -r '.letsencrypt.Certificates[]?.domain.main' acme.json

# router enumeration
curl -s http://localhost:8083/api/http/routers | jq -r '.[] | "\(.name)\t\(.status)\t\(.rule)"'

# tcp router enumeration
curl -s http://localhost:8083/api/tcp/routers | jq

# test public host
curl -skI https://<host>.ai-servicers.com

# test mail TCP
nc -zv mail.ai-servicers.com 993
```

## Backup
- Critical: `acme.json` (private keys for all certs). Snapshot before any destructive op.
- Important: `traefik.yml`, `redirect.yml`, `docker-compose.yml`, `secrets/traefik.env`.
- Recoverable from source: container labels (in each service's `deploy.sh`).
