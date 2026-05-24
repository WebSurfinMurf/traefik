# Testing

## Strategy
- No unit tests — this is a config-driven project, not a code-bearing one.
- Verification is end-to-end: probe routers + public hosts + logs after every change.

## Critical Paths to Verify

### After any deploy
1. Container up: `docker ps --filter name=^traefik$ --format '{{.Status}}'` — should show `Up`.
2. Health check: `docker exec traefik wget -qO- http://localhost:8083/api/version | grep Version`.
3. Router count sanity: `curl -s http://localhost:8083/api/http/routers | jq 'length'` — expect >7 (file+internal only is 7; docker provider should add many more, currently 70+).
4. Provider breakdown sanity: `curl -s http://localhost:8083/api/http/routers | jq -r '.[].provider' | sort | uniq -c` — expect both `file` and `docker` represented.

### After image upgrade
- Above, plus: spot-check 3-5 public hosts return non-404 (`curl -skI https://<host>.ai-servicers.com`).
- Mail TCP probe: `nc -zv mail.ai-servicers.com 993`.

### ACME renewal
- `docker logs traefik --since 1h | grep -iE 'acme.*(error|fail)'` — should be empty.
- `jq -r '.letsencrypt.Certificates[]?.domain.main' acme.json` — confirm expected cert list.
- For any cert: `echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | openssl x509 -noout -dates`.

## Regression Checks
- After Traefik upgrade: verify dashboard + 3-5 services + mail TCP. The 2026-05-08 v3.4 → v3.6 upgrade required this protocol because v3.4's docker provider had silently broken.
- After `--remove-orphans` deploy: verify expected sidecars still present (`docker ps | grep traefik`). The 2026-05-08 upgrade removed `traefik-docker-proxy` as an unintended side effect.
- After Cloudflare DNS change: re-test all hosts that point through the changed records, plus verify a sample ACME renewal can complete (e.g., force a cert reissue by removing one entry from `acme.json`).

## Coverage Gaps (acknowledged)
- No automated regression suite. All testing is manual / scripted in deploy.sh.
- No synthetic monitoring of cert renewal paths — only reactive log inspection.
- No alerting on `cloudflare: failed to find zone` errors. (Future: Grafana alert wired to Loki.)
