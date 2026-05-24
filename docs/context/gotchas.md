# Gotchas

<!-- Format: SYMPTOM > CAUSE > FIX. Organize by area. -->

## Docker Provider / API Version

- **Symptom**: All `traefik.enable=true` hosts return 404. File-provider routers (acme-challenge, redirects) still work. Logs show repeated `Failed to retrieve information of the docker client and server host error="client version 1.24 is too old"`.
- **Cause**: Traefik 3.4.x's embedded Go Docker SDK pins API v1.24. Docker daemons with `MinAPIVersion ≥ 1.44` (modern releases) reject it. `DOCKER_API_VERSION` env var has no effect — Traefik's client is not constructed with `client.FromEnv`.
- **Fix**: Pin `TRAEFIK_IMAGE` to ≥ v3.5 in `secrets/traefik.env`; v3.5+ rebuilt the client with API version negotiation. (Resolved 2026-05-08 via v3.4.3 → v3.6.16.)

## ACME / Cloudflare DNS-01

- **Symptom**: Renewal fails for every cert with `cloudflare: failed to find zone <foreign-zone>.: zone could not be found`.
- **Cause**: Cloudflare wildcard CNAME on the zone (`*.X CNAME <foreign>.tld`) synthesizes responses for every undefined name, including `_acme-challenge.<anything>.X`. lego's `FindZoneByFqdn` follows the CNAME and walks the SOA chain of the target, landing on `<foreign>.tld`'s SOA. The Cloudflare provider then asks the API for that zone → not hosted → fails.
- **Fix (resolved 2026-05-23)**: Wildcard CNAME repointed from `embracenow.asuscomm.com` (foreign zone) to `home.ai-servicers.com` (in-zone A record maintained by `projects/ddns-updater`). SOA walk now terminates in `ai-servicers.com` → Cloudflare → API succeeds. Stopgap "explicit TXT pre-empts wildcard" pattern also works in emergencies; see `docs/acme-renewal-2026-05-08/PLAN.md`.

## Cloudflare wildcard precedence

- **Symptom**: Adding a narrower wildcard record (e.g., `_acme-challenge.*.X TXT "stub"`) does NOT pre-empt a broader wildcard (e.g., `*.X CNAME ...`) for child names. Direct queries against CF's authoritative NS still return the broader CNAME for `_acme-challenge.foo.X`.
- **Cause**: Cloudflare does not implement RFC 4592 closest-encloser matching for cascading wildcards. The first wildcard encountered in the namespace tree wins; narrower ones at deeper namespaces don't override.
- **Fix**: Use explicit (non-wildcard) records at the exact names you want to pre-empt, OR restructure so only one wildcard exists in the namespace at a given depth.

## Cloudflare CNAME flattening — non-apex restricted to paid plans

- **Symptom**: `POST /zones/.../dns_records` with `settings.flatten_cname: true` on a non-apex record returns `error 9226: "CNAME flattening is not available to this zone."`.
- **Cause**: Cloudflare Free/Pro plans only support CNAME flattening at the **zone apex**. Per-record `flatten_cname` on subdomains (including wildcards) is Enterprise-only.
- **Fix**: Don't rely on non-apex flattening as a design option. If you need "CNAME that returns an A at serve time" behavior on a Free plan, do it at the apex or use a real A record with external automation (DDNS updater).

## Apex on `proxied=true` + ddns-updater

- **Symptom**: ddns-updater logs `Last ipv4 address stored for ai-servicers.com is invalid IP and your ipv4 address is X` and re-issues an apex update on every cycle, even though no change is needed.
- **Cause**: qdm12 resolves `ai-servicers.com` from public DNS to compare against the detected public IP. With `proxied=true`, public DNS returns Cloudflare anycast IPs, not the origin → always "different" → triggers redundant API write.
- **Fix**: CF API write is idempotent (no actual record change), so this is log noise rather than a functional issue. If noise becomes a problem: remove apex from ddns-updater config and manage manually, OR use a DDNS tool that compares against the CF API directly instead of public DNS for proxied records.

## Deploy / Orphans

- **Symptom**: A sidecar container defined outside this compose file (e.g., `traefik-docker-proxy` from a separate compose context) disappears after `./deploy.sh`.
- **Cause**: `docker compose up -d --remove-orphans` is enabled in `deploy.sh`. Compose treats anything labeled with this compose project but not in the current YAML as orphan, regardless of which project file created it.
- **Fix**: Either include the sidecar in this compose file, OR deploy it from its own compose with a distinct project name (so it has a different label). Document any externally-deployed sidecars that depend on Traefik in the project README.

## NAT Reflection (host LAN IP from containers)

- **Symptom**: Container on Docker network cannot reach a service hosted on this same machine via its public hostname (e.g., Nextcloud → Mailserver via `mail.ai-servicers.com`).
- **Cause**: ASUS Merlin router does not NAT-reflect. Public hostname resolves to public IP; container tries to hairpin through router; router drops the loopback connection.
- **Fix**: Configure the container to use external DNS (`dns: [8.8.8.8]`) AND add a hosts entry mapping the public hostname to the container's Docker network IP (e.g., `extra_hosts: ["mail.ai-servicers.com:172.22.0.17"]`). Mailserver workaround documented in `nextcloud` project.

## Multi-Service Container Labels

- **Symptom**: Traefik logs `Router X cannot be linked automatically with multiple Services: ["service1" "service2"]`. Router doesn't load.
- **Cause**: Container exposes more than one Traefik service (e.g., GitLab + Container Registry on different ports). Traefik can't auto-pick which one the router maps to.
- **Fix**: Add explicit `traefik.http.routers.<name>.service=<service-name>` label on each router, paired with `traefik.http.services.<service-name>.loadbalancer.server.port=<port>`.

## Static Container IP Conflicts

- **Symptom**: Traefik fails to start with IP conflict on `172.25.0.6`.
- **Cause**: Another container grabbed Traefik's static IP slot on `traefik-net`.
- **Fix**: `deploy.sh` includes auto-reconcile: detects conflict, disconnects/reconnects the offending container with dynamic IP, then proceeds. Manual fix: `docker network disconnect traefik-net <other> && docker network connect traefik-net <other>`.
