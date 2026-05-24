---
name: acme-ddns-arch-collision
created: 2026-05-08
status: pending-review
---

# DNS architecture collision: wildcard CNAME for DDNS vs lego DNS-01 ACME on the same Cloudflare zone

## Situation

Traefik on a homelab server (`linuxserver.lan`, ~78 containers, all public Tier-2 services fronted by Traefik on `*.ai-servicers.com`) is failing to renew Let's Encrypt certificates. Existing certs expire in 3–26 days; the wildcard cert (covering most services) expires in 7 days. Investigation today identified a **structural DNS collision** between the residential DDNS implementation and the ACME DNS-01 challenge mechanism, both operating on the same Cloudflare zone.

This is not a stale-config bug. It is two requirements that share a name space and an underlying mechanism (a wildcard CNAME) that satisfies one and fundamentally breaks the other. I am asking the Review Board to gut-check the architectural framing and the recommended fix before I execute anything.

### Verified facts

**Zone state (Cloudflare, snapshot 2026-05-08T21:18Z, 17 records total):**

| Name | Type | Content | Notes |
|---|---|---|---|
| `*.ai-servicers.com` | **CNAME** | **`embracenow.asuscomm.com`** | Load-bearing record. Synthesizes responses for every undefined name in the zone. |
| `ai-servicers.com` (apex) | CNAME | `embracenow.asuscomm.com` | Apex CNAME, works on Cloudflare via CNAME flattening. |
| `mailu.ai-servicers.com` | CNAME | `embracenow.asuscomm.com` | Explicit even though wildcard would cover it. |
| `em903…`, `brevo…`, `s1/s2._domainkey…` | CNAME | sendgrid / brevo | Email delivery. |
| MX × 3 | MX | `routeN.mx.cloudflare.net` | Cloudflare email routing. |
| TXT × 6 | TXT | SPF, DKIM (cf2024-1, mail), DMARC, brevo verification, google site verification | |

There are **no** explicit `_acme-challenge.*.ai-servicers.com` records. Every query for such names is synthesized by the wildcard CNAME.

**DDNS chain:**
- `embracenow.asuscomm.com` lives on the `asuscomm.com` zone (ASUS DDNS).
- ASUS router updates that A record when the residential external IP changes.
- Today: `108.35.80.85`.
- Cloudflare API token has zone-edit on `ai-servicers.com` only. No rights on `asuscomm.com` (and never can — ASUS administers it).

**ACME failure trace:**
1. lego (Traefik 3.6.16's bundled `github.com/go-acme/lego`) decides to write a TXT at `_acme-challenge.<host>.ai-servicers.com`.
2. lego calls `FindZoneByFqdn("_acme-challenge.<host>.ai-servicers.com.")` — recursive SOA query through the system resolver.
3. Resolver follows the wildcard CNAME (synthesized) → `embracenow.asuscomm.com`.
4. SOA walk on the canonical name lands on `asuscomm.com`'s SOA (`ns1.asuscomm.com`).
5. lego's Cloudflare provider queries `GET /zones?name=asuscomm.com` → empty → `cloudflare: failed to find zone asuscomm.com.: zone could not be found` → renewal fails.

**Log evidence (continuous, every renewal cycle):**
```
ERR Error renewing ACME certificate: {<host> []}
   error="cloudflare: failed to find zone asuscomm.com.: zone could not be found"
   acmeCA=https://acme-v02.api.letsencrypt.org/directory providerName=letsencrypt.acme
```

**Certificate expirations (relative to today, 2026-05-08):**

| Cert | Expires | Days |
|---|---|---:|
| `registry.gitlab.ai-servicers.com` | 2026-05-11 | **3** |
| `ai-servicers.com` + `*.ai-servicers.com` | 2026-05-15 | 7 |
| `open-webui.ai-servicers.com` | 2026-05-15 | 7 |
| `diagrams.nginx.ai-servicers.com` | 2026-06-03 | 26 |

**Recent change history:**
- Today (2026-05-08): Traefik bumped `v3.4.5` → `v3.6.16` to fix an unrelated Docker daemon API negotiation issue (separate refocus brief, completed).
- CNAME records show `modified_on: 2026-03-12T20:41`. Certs were issued ~Feb 2026. Plausible that a change in lego's SOA-walk behavior between bundled versions made today's failure visible. The architecture has been ambient-broken; only the symptom timing changed. (Unverified; no DNS history available.)

## Architectural framing of the problem

The zone serves two concerns sharing the same name space:

1. **Dynamic-IP propagation (DDNS)** — every Tier-2 service (`<svc>.ai-servicers.com`) must resolve to the residential external IP, which can change.
2. **ACME DNS-01 challenge response** — `_acme-challenge.<svc>.ai-servicers.com TXT` must be writable by lego (via the configured Cloudflare API token) for cert issuance/renewal.

Current implementation collapses both onto a single mechanism: a wildcard CNAME pointing into a third-party zone (`asuscomm.com`).

This works for concern #1 (cheap, leverages the ASUS router's DDNS client). It is structurally incompatible with concern #2: a CNAME response from the wildcard hijacks every name lookup under the zone — including ones whose SOA walk must land within an API-writable zone. Cloudflare has no jurisdiction over `asuscomm.com`, and won't ever.

This is not a config bug. It is a chosen architecture whose two requirements collide. Any "fix" that doesn't address the architectural collision is patching a symptom.

## Solution candidates

### Solution A — Replace CNAME-based DDNS with API-driven A-record DDNS (recommended)

Move DDNS off the DNS chain and onto an API push.

**Changes:**
1. Deploy a DDNS updater (e.g., `oznu/cloudflare-ddns`, `timothymiller/cloudflare-ddns`, or a small custom script) that monitors external IP and updates Cloudflare A records via the existing CF API token.
2. Change apex `ai-servicers.com` from CNAME → A (managed by the updater).
3. Change `*.ai-servicers.com` from CNAME → CNAME *to the apex* (`ai-servicers.com`). Stays inside the Cloudflare zone.
4. Remove `mailu.ai-servicers.com` CNAME if redundant after step 3 (or leave as explicit).
5. ASUS DDNS becomes vestigial; can keep enabled as redundancy or disable.

**Why architecturally correct:**
- One source of truth for the residential external IP: the apex A record at Cloudflare, updated via CF API.
- Wildcard CNAME stays — it now points within the same zone, so SOA walks always terminate on `ai-servicers.com SOA` (Cloudflare). ACME just works.
- DDNS is a process (push to API on IP change), not a DNS chain across providers.
- Zone is fully self-contained; no third-party zone in any resolution path.
- Onboarding a new service: add labels in Traefik. No DNS edits, no ACME placeholders.

**Risks/costs:**
- Need to deploy and operate the DDNS updater.
- During DDNS-updater bring-up, IP could change without propagation.
- ASUS router still does its thing for asuscomm.com; no change needed there.

### Solution B — Delegated `_acme-challenge` subzone (canonical "ACME CNAME delegation")

Decouple ACME from DDNS at the DNS layer rather than the architecture layer.

**Changes:**
1. Create a new zone authoritative for `_acme-challenge.ai-servicers.com` (sub-zone on Cloudflare, or a dedicated ACME-friendly provider like deSEC.io).
2. Add NS records: `_acme-challenge.ai-servicers.com NS <new zone>`.
3. Configure Traefik with a second DNS provider for the new zone.
4. Wildcard CNAME unchanged.

**Why architecturally clean:**
- Concerns separated by DNS layer: DDNS owns `*.ai-servicers.com`, ACME owns `_acme-challenge.ai-servicers.com`.
- Wildcard CNAME's behavior no longer matters for ACME.

**Risks/costs:**
- Second DNS provider/zone to maintain.
- Second API credential.
- More moving parts.
- Doesn't fix the smell of the DDNS chain itself; third-party zone still in resolution path for normal traffic.

### Solution C — Pre-populate explicit `_acme-challenge.<host>` placeholders (rejected)

Add an explicit non-CNAME record at each `_acme-challenge.<host>.ai-servicers.com` to pre-empt the wildcard for that name.

**Why rejected:**
- Treats a structural collision as a per-record patch.
- Operational sharp edge: every new cert host requires remembering to add a placeholder. Forgotten placeholders = failed renewals days later.
- Solves the symptom; leaves the underlying architecture broken.

Acceptable as a 30-minute emergency patch if cert deadlines force action before any architectural change can land. Not acceptable as steady state.

### Solution D — Drop wildcard, write per-service explicit A records (rejected on cost)

**Why rejected vs A:** strictly more work (N records to update on every IP change vs 1). No architectural advantage over A, which is the special case where the apex is the only A record and a same-zone CNAME wildcard inherits.

## Recommendation

**Solution A.**

Justifications:
- Single source of truth for residential IP (apex A in Cloudflare).
- Zone self-contained; no foreign zone in any resolution path.
- ACME works as a side effect of architecture being right, not a bolt-on.
- Lowest operational sharp-edge: zero per-service DNS work for new services.
- Reversible: switch the apex back to CNAME → embracenow.asuscomm.com if returning to ASUS DDNS later.

**Implementation order, deadline-aware:**
1. Hour 0 — Deploy DDNS updater container against the apex A. Verify match with current external IP.
2. Hour 0–1 — Switch wildcard CNAME from `embracenow.asuscomm.com` → `ai-servicers.com`. Verify resolution from external (CF propagation <5min).
3. Hour 1 — Remove redundant `mailu` CNAME, or leave.
4. Hour 1–2 — Force re-issuance of `registry.gitlab` (3-day deadline) by removing its acme.json entry and restarting Traefik. Verify.
5. Hour 2 — Force re-issuance of remaining failing certs.
6. Day 1 — Drop standalone `open-webui` cert (covered by wildcard via SNI).
7. Day 1–2 — Doc updates.

## What I Need

Specific questions for the Review Board:

1. **Is Solution A architecturally correct?** If not, what's the alternative the analysis missed? Specifically: is delegation (B) more correct because it preserves "ASUS owns DDNS, Cloudflare owns ACME" as a clean separation of providers?

2. **Hidden risks in Solution A I haven't surfaced?** Examples I considered and discarded:
   - DNSSEC interaction with apex CNAME → A change (zone is not DNSSEC-signed today; verified).
   - Cloudflare proxy mode on apex (currently proxied: true; A record can also be proxied).
   - CF API rate limits on the DDNS updater (residential IP changes rarely; well within CF's 1200/5min).
   - SPF/DKIM/DMARC: SPF references `a:mail.ai-servicers.com`, not the apex; DKIM/DMARC are TXT, unaffected.
   - Email routing: MX records point at Cloudflare email routing, independent of A/CNAME chain. Nothing should break.

3. **Is the implementation order safe**? Specifically: deploy updater → cut over wildcard target → renew certs. Any reordering or precaution that should land first?

4. **Is the lego-version-change hypothesis worth verifying** before declaring root cause closed? Or is the architectural fix the right move regardless of when the symptom appeared?

5. **Anything in the broader project context** (multi-service homelab, ~78 containers, Traefik fronting all public services, mail server in mix) that this proposal would damage and an outsider would notice but I'd miss because I'm too close?

## Constraints

- **Time:** `registry.gitlab` cert expires 3 days from today (2026-05-11). Wildcard expires 7 days. Architectural fix should land before those deadlines, OR a justified emergency patch (Solution C) should land first as a stopgap.
- **Tech stack:** Cloudflare DNS (existing), Traefik 3.6.16, lego (bundled), Docker Compose, residential ISP with dynamic IP, ASUS router (Merlin firmware) with built-in DDNS to asuscomm.com.
- **Already ruled out:** HTTP-01 challenge (breaks wildcard); changing certificate authority; renaming services to single-label form (downstream client churn).
- **Authority:** I have CF API token with zone-edit on `ai-servicers.com`. I do not have admin on `asuscomm.com` — that's ASUS DDNS service, not user-controlled.
- **Decision style:** user explicitly said "I am not looking for 'easy', I am looking for architecturally correct" — so trade-offs should favor architectural cleanliness over implementation simplicity, within reason.

## Reference (paths from review-board read-only mount perspective)

- `/workspace/administrator/projects/traefik/docs/acme-renewal-2026-05-08/SITUATION-AND-RECOMMENDATION.md` — the original write-up this review file is derived from. Same content, slightly different framing.
- `/workspace/administrator/projects/traefik/docs/acme-renewal-2026-05-08/PLAN.md` — the FIRST plan, now superseded. Documents the wrong-turn reasoning before the wildcard finding (was going to delete `_acme-challenge` records that turned out not to exist).
- `/workspace/administrator/projects/traefik/docs/acme-renewal-2026-05-08/cf-acme-records-before.json` — empty array; confirms no explicit `_acme-challenge` records exist.
- `/workspace/administrator/projects/traefik/docs/acme-renewal-2026-05-08/cf-all-records-raw.json` — full Cloudflare zone snapshot (17 records).
- `/workspace/administrator/projects/traefik/CLAUDE.md` — current Traefik project state, including "Open Issues" entry for the ACME failure added today.
- `/workspace/administrator/projects/traefik/traefik.yml` — Traefik static config (certificatesResolvers section).
- `/workspace/administrator/projects/traefik/docker-compose.yml` — Traefik container config.
- `/workspace/administrator/projects/CLAUDE.md` — master infrastructure index.
