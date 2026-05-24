---
id: 2026-05-08-fix-docker-provider-api-8c0cbd
status: result
child_session_id: 8c0cbd4c-855a-43ac-a04f-7517f3bc98c8
spawn_mode: manual
spawned_at: 2026-05-08T15:52:44Z
launched_at: 2026-05-08T15:55:00Z
completed_at: 2026-05-08T16:16:00Z
source_dir: /home/administrator/projects/dashy
source_session_id: 42ae9c9d-f674-4de4-b517-6249baa891b0
dest_dir: /home/administrator/projects/traefik
slug: fix-docker-provider-api
parent_refocus_id: null
related_refocus_ids: []
done_when:
  - "https://dashy.ai-servicers.com returns dashy/Keycloak redirect (not 404)"
  - "At least one other previously-broken host (keycloak/grafana/gitlab) responds with expected status"
  - "Traefik API at localhost:8083/api/http/routers shows >7 routers including dashy@docker"
  - "docker logs traefik no longer emits 'client version 1.24 is too old'"
out_of_scope:
  - "Modifying dashy-specific config (dashy is not the problem)"
  - "Touching Keycloak, GitLab, or any other downstream service deploy"
  - "Refactoring traefik.yml beyond what is required to fix docker provider negotiation"
related: []
---

# Brief: Fix Traefik docker provider — API version negotiation

## Why this branch exists
Today (2026-05-08) the user reported "can't get to dashy from public URL." Investigation in the dashy session showed dashy itself is healthy — the failure is system-wide: Traefik 3.4.5's docker provider can't negotiate API version with the upgraded Docker daemon. The daemon now requires `MinAPIVersion 1.44` but Traefik keeps requesting `/v1.24/version`. Result: zero docker-defined routers load, and every Traefik-routed service returns 404. Continuing in `projects/traefik/` because the fix touches `docker-compose.yml`, `traefik.yml`, possibly `secrets/traefik.env`, and may require an image upgrade or sidecar reconfiguration.

## Inherited context
- All Traefik-routed hosts return 404: dashy, keycloak, grafana, portainer, gitlab — confirmed via curl from the source session.
- Traefik logs (continuous): `ERR Failed to retrieve information of the docker client and server host error="client version 1.24 is too old. Minimum supported API version is 1.44" providerName=docker`
- Traefik runtime: `Version: 3.4.5`. Image tag in compose: `traefik:v3.4` (moving tag).
- Docker daemon: `Server API: 1.52, MinAPI: 1.44`.
- Container `traefik` already has `DOCKER_API_VERSION=1.44` baked into env (loaded from `$HOME/projects/secrets/traefik.env` via compose `env_file`). The Traefik docker SDK is **not honoring it** — outbound requests still hit `/v1.24/version`. So a plain `docker restart traefik` is unlikely to fix anything; same env, same negotiation, same failure.
- Traefik mounts the docker socket directly (`/var/run/docker.sock:/var/run/docker.sock:ro` in `docker-compose.yml`); it does **not** route through the running `traefik-docker-proxy` sidecar.
- `traefik-docker-proxy` sidecar (image `nginx:alpine`) has its own latent break: logs from 2026-04-18 show `connect() to unix:/var/run/docker.sock failed (13: Permission denied)`. Switching to it would require fixing socket perms on the proxy first — not a free option.
- Surviving routers (file provider only, 7 total): `acme-challenge-router@file`, `homepage-router@file`, `nginx-livekit-debug@file`, `redirect-router@file`, plus `api@internal`, `dashboard@internal`, `prometheus@internal`. That's why a few things still work and most don't.
- `dashy` and `dashy-auth-proxy` containers are healthy; networks correct (`dashy-net`, `traefik-net`, `keycloak-net`); labels on `dashy-auth-proxy` are correct (`Host(\`dashy.ai-servicers.com\`)`, port 4180). **No dashy-side changes needed.**
- DNS ruled out: Traefik returns clean HTTP/2 404 (TCP+TLS+HTTP all complete). Quote: `dig +short dashy.ai-servicers.com → 192.168.1.13`.
- User has not yet authorized any restart, image bump, or other destructive action — confirm before each step. They were skeptical that DNS/restart could be the cause, and were given an explanation of why neither is.
- Outage blast radius: ~78 running containers, most public Tier-2 apps front through Traefik. This is platform-wide, not service-specific.
- Project files of interest: `projects/traefik/docker-compose.yml`, `projects/traefik/traefik.yml`, `projects/traefik/deploy.sh`, `projects/secrets/traefik.env`, plus the `projects/traefik/docker-proxy/` subdir (likely the sidecar's compose).

## Open questions / desired deliverables
- Restore docker-provider routing so all `traefik.enable=true` containers register again.
- Pick the fix path:
  - (a) `docker restart traefik` as a 5-second sanity test — expected to fail but cheap to confirm.
  - (b) Bump image to a Traefik release whose docker client supports modern API negotiation (or honors `DOCKER_API_VERSION`). Investigate which Traefik tag fixes this; 3.4.5 is current 3.4 but the negotiation bug may be patched in 3.5+.
  - (c) Switch Traefik to consume the `traefik-docker-proxy` sidecar at `tcp://traefik-docker-proxy:2375` — requires fixing the proxy's socket-perms break first.
- Verify `dashy.ai-servicers.com` plus at least one other host respond correctly post-fix.
- Update `projects/traefik/CLAUDE.md` with incident + resolution notes.

## Hard rule for child
- Children are leaves. If you discover work that belongs in a different
  directory, do NOT call /refocus. Surface it in Result.suggested_follow_ups
  for the parent to decide.

## Pointer back
- Source session: `~/.claude/projects/-home-administrator-projects-dashy/42ae9c9d-f674-4de4-b517-6249baa891b0.jsonl`
- To continue this child later: `cd /home/administrator/projects/traefik && claude --resume 8c0cbd4c-855a-43ac-a04f-7517f3bc98c8`

---

## Result

### Status
- completed

### Definition-of-Done met
- ✅ `https://dashy.ai-servicers.com` returns dashy/Keycloak redirect (HTTP 302 → `keycloak.ai-servicers.com/realms/master/protocol/openid-connect/auth?...&client_id=dashy&...`).
- ✅ Other previously-broken hosts respond non-404: keycloak (302), gitlab (302), grafana (403 — auth, not Traefik 404).
- ✅ Traefik API at `localhost:8083/api/http/routers` shows 81 routers (74 docker, 4 file, 3 internal), including `dashy@docker` enabled.
- ✅ `docker logs traefik` no longer emits `client version 1.24 is too old`. Docker provider operating cleanly.

### Summary
The fix was a Traefik image bump. Edited `secrets/traefik.env` to set `TRAEFIK_IMAGE=traefik:v3.6.16` (was `v3.4.3`; running was `v3.4.5`) and ran `projects/traefik/deploy.sh`. Traefik 3.5+ rebuilt the embedded Docker SDK client to negotiate API version with the daemon; 3.4.x asks for `/v1.24/version` regardless of `DOCKER_API_VERSION` env (its client wasn't built with `client.FromEnv`). Restart alone would not have fixed it. Post-deploy, Traefik 3.6.16 came up clean, all docker-discovered routers reloaded, and platform-wide routing is restored. Total image-related downtime ~10s during container recreate.

### Artifacts produced
- `/home/administrator/projects/secrets/traefik.env` — `TRAEFIK_IMAGE` bumped `v3.4.3` → `v3.6.16`.
- `/home/administrator/projects/traefik/CLAUDE.md` — added 2026-05-08 incident + resolution under Resolved Issues; added new "Open Issues" section noting pre-existing ACME failure; bumped Last Updated.

### Suggested follow-ups (parent decides)
- `/home/administrator/projects/traefik` — slug `fix-acme-cloudflare-zone` — Traefik logs `cloudflare: failed to find zone asuscomm.com` on every renewal attempt for `*.ai-servicers.com`, `open-webui.ai-servicers.com`, `diagrams.nginx.ai-servicers.com`, `registry.gitlab.ai-servicers.com`. Pre-existing (not caused by this upgrade); existing certs still valid. Resolver/zone config in `traefik.yml` or env needs correction before next renewal cycle, or HTTPS will start failing as certs expire.
- `/home/administrator/projects/traefik` — slug `cleanup-traefik-docker-proxy-sidecar` — `--remove-orphans` removed the `traefik-docker-proxy` (`nginx:alpine`) sidecar during this deploy. It was already broken (socket perms, per source brief) and unused (Traefik mounts the docker socket directly). The `projects/traefik/docker-proxy/` dir still holds an `nginx.conf`. Decide: delete the dir, or restore the sidecar from a separate compose context if it's wanted.

### Material changes (for /context-save)
- **gotchas** — Traefik docker-provider requires v3.5+ against Docker daemons with `MinAPIVersion ≥ 1.44`. v3.4.x's embedded Docker SDK pins `/v1.24` and silently emits `Provider error, retrying...` until every docker-defined router stops loading. `DOCKER_API_VERSION` env has no effect. Symptom: platform-wide 404 on `traefik.enable=true` hosts while file/internal routers continue serving.
- **operations** — `TRAEFIK_IMAGE` is pinned in `secrets/traefik.env` (currently `v3.6.16`). Upgrade path is: edit that var, run `projects/traefik/deploy.sh`. `--remove-orphans` is enabled in deploy; sidecars not in `projects/traefik/docker-compose.yml` will be culled.

### Child session
- Session jsonl: `~/.claude/projects/-home-administrator-projects-traefik/8c0cbd4c-855a-43ac-a04f-7517f3bc98c8.jsonl`
- Completed at: 2026-05-08T16:16:00Z

<!--
When the child completes, /refocus-complete appends here:

### Status
- completed       # met all done_when criteria
- blocked         # hit a blocker requiring work in another directory; parent must orchestrate

### Definition-of-Done met
<checklist matching done_when from frontmatter, each item checked or noted as not met>

### Summary
<one paragraph: what was accomplished or where it blocked>

### Artifacts produced
- `<path>` — `<one-line description>`

### Suggested follow-ups (parent decides)
<bullets of "I noticed work belongs at <dir>" items the child surfaced for
parent to orchestrate. Each entry: dir, slug, one-line reason.>

### Material changes (for /context-save)
<list of decisions, contracts, or architecture changes that should be
promoted into <dest>/docs/context/* as canonical state. Each entry: which
context file (architecture | interfaces | conventions | gotchas | …) and
the one-line summary. Or: "N/A — investigation only, no canonical state
changed." Mandatory; child must enumerate explicitly before status flips.>

### Child session
- Session jsonl: `~/.claude/projects/-home-administrator-projects-traefik/8c0cbd4c-855a-43ac-a04f-7517f3bc98c8.jsonl`
- Completed at: <ISO ts>
-->
