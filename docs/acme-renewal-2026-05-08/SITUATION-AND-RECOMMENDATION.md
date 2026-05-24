# ai-servicers.com — DNS / ACME architectural situation and recommendation

**Date:** 2026-05-08
**Author:** Claude (administrator's session)
**Audience:** AI Review Board (Gemini, Codex, Claude reviewer)
**Purpose:** Get a structured second opinion on the architecturally correct fix for an ACME renewal failure that is rooted in a DNS-architecture collision, not in stale config.

---

## 1. Verified facts

### 1.1 Zone state (Cloudflare, snapshotted 2026-05-08T21:18Z)

Authoritative for `ai-servicers.com`: `dell.ns.cloudflare.com`, `west.ns.cloudflare.com`. CF API token (`CF_DNS_API_TOKEN` in `secrets/traefik.env`) has zone-edit on `ai-servicers.com` only — verified working.

Total records: 17. Key entries:

| Name | Type | Content | Notes |
|---|---|---|---|
| **`*.ai-servicers.com`** | **CNAME** | **`embracenow.asuscomm.com`** | The load-bearing record. Synthesizes responses for every undefined name in the zone. |
| `ai-servicers.com` (apex) | CNAME | `embracenow.asuscomm.com` | Apex CNAME — works on Cloudflare via CNAME flattening (proxied: true). |
| `mailu.ai-servicers.com` | CNAME | `embracenow.asuscomm.com` | Explicit even though wildcard would cover it. |
| `em903…`, `brevo1/2._domainkey…`, `s1/s2._domainkey…` | CNAME | sendgrid / brevo | Email delivery infrastructure. |
| `ai-servicers.com` × 3 | MX | `routeN.mx.cloudflare.net` | Cloudflare email routing. |
| `ai-servicers.com`, `_dmarc`, `cf2024-1._domainkey`, `mail._domainkey` | TXT | SPF/DKIM/DMARC, brevo verification, google site verification | |

There are **no** explicit `_acme-challenge.*.ai-servicers.com` records. Every query for such names is synthesized by the wildcard CNAME.

### 1.2 DDNS chain

`embracenow.asuscomm.com` lives on the `asuscomm.com` zone (ASUS DDNS service). Its A record is updated by the user's ASUS router when the residential external IP changes. Today: `108.35.80.85`. The CF API token has no rights on `asuscomm.com` and never can — the user does not own that zone administratively; ASUS does.

### 1.3 ACME failure mode

Traefik (now `v3.6.16` after today's earlier fix) ships lego (`github.com/go-acme/lego`) for ACME. Logs show, on every renewal attempt:

```
ERR Error renewing ACME certificate: {<host> []}
   error="cloudflare: failed to find zone asuscomm.com.: zone could not be found"
   acmeCA=https://acme-v02.api.letsencrypt.org/directory providerName=letsencrypt.acme
```

Trace:
1. lego decides to write a TXT at `_acme-challenge.<host>.ai-servicers.com`.
2. lego calls `FindZoneByFqdn("_acme-challenge.<host>.ai-servicers.com.")` — a recursive SOA query through the system resolver.
3. The resolver follows the wildcard CNAME (synthesized) → `embracenow.asuscomm.com`.
4. SOA walk on the canonical name lands on `asuscomm.com`'s SOA (`ns1.asuscomm.com`).
5. lego's Cloudflare provider then asks `GET /zones?name=asuscomm.com` → empty result → "zone could not be found" → renewal fails.

### 1.4 Certificate expirations

| Cert | Expires | Days from 2026-05-08 |
|---|---|---:|
| `registry.gitlab.ai-servicers.com` | 2026-05-11 | **3** |
| `ai-servicers.com` + `*.ai-servicers.com` | 2026-05-15 | 7 |
| `open-webui.ai-servicers.com` | 2026-05-15 | 7 |
| `diagrams.nginx.ai-servicers.com` | 2026-06-03 | 26 |

Every service routed under `*.ai-servicers.com` (~20+ Tier-2 apps) loses HTTPS if the wildcard expires.

### 1.5 What changed and when

- Today (2026-05-08): Traefik bumped from `v3.4.5` → `v3.6.16` to fix an unrelated Docker daemon API negotiation issue (separate refocus brief, completed; see `docs/refocus/2026-05-08-fix-docker-provider-api-8c0cbd.md`).
- The CNAME records show `modified_on: 2026-03-12T20:41`. So they're at least ~2 months old. The certs in `acme.json` were issued ~Feb 2026 (90 days back from `notAfter` = May 15). It's plausible the wildcard CNAME predates the certs and renewals worked under Traefik 3.4's lego version — i.e., a behavior change in lego between the bundled versions made today's failure visible. (Unverified; no DNS history available.) Either way, the architecture has been ambient-broken; only the symptom timing changed.

---

## 2. Architectural framing of the problem

The zone serves two concerns sharing the same name space:

1. **Dynamic-IP propagation (DDNS)** — every Tier-2 service (`<svc>.ai-servicers.com`) must resolve to the residential external IP, which can change.
2. **ACME DNS-01 challenge response** — `_acme-challenge.<svc>.ai-servicers.com TXT` must be writable by lego (via the configured Cloudflare API token) for cert issuance/renewal.

The current implementation collapses both concerns into a single mechanism: a wildcard CNAME pointing into a third-party zone (`asuscomm.com`).

This works for concern #1 (cheap, leverages the ASUS router's built-in DDNS client). It is structurally incompatible with concern #2: a CNAME response from the wildcard hijacks every name lookup under the zone — including ones whose SOA walk must land within an API-writable zone. Cloudflare has no jurisdiction over `asuscomm.com`, and won't ever.

This is not a config bug. It is a chosen architecture whose two requirements collide. Any "fix" that doesn't address the architectural collision is patching a symptom.

---

## 3. Solution candidates

### Solution A — Replace CNAME-based DDNS with API-driven A-record DDNS (recommended)

Move DDNS off the DNS-chain and onto an API push.

**Changes:**
1. Deploy a DDNS updater that monitors the external IP and updates Cloudflare A records via the existing CF API token. Open-source options that fit this server's posture: `oznu/cloudflare-ddns` (Docker), `timothymiller/cloudflare-ddns` (Python), or a small custom shell+curl loop. All idempotent, all containerizable.
2. Change apex `ai-servicers.com` from CNAME → A (managed by the updater).
3. Change `*.ai-servicers.com` from CNAME → CNAME *to the apex* (`ai-servicers.com`). Stays inside the Cloudflare zone.
4. Remove `mailu.ai-servicers.com` CNAME if redundant after step 3 (or leave as explicit).
5. ASUS DDNS becomes vestigial; can keep enabled as a redundancy or disable.

**Why this is architecturally correct:**
- One source of truth for the residential external IP: the apex A record at Cloudflare, updated via CF API.
- Wildcard CNAME stays — it now points within the same zone, so SOA walks always terminate on `ai-servicers.com SOA` (Cloudflare). ACME just works.
- DDNS is a process (push to API on IP change), not a DNS chain across providers.
- Zone is fully self-contained; no third-party zone in any resolution path.
- Onboarding a new service: add labels in Traefik. No DNS edits needed. No ACME placeholders needed.

**Risks / costs:**
- Need to deploy and operate the DDNS updater. Single point of failure if it stops; falls back to "current A record stays static" — still works until next IP change. Easy to monitor (Promtail picks up logs; alert on failure).
- During the DDNS-updater bring-up, IP could change without propagation. Mitigation: bring up updater first, observe one IP push (or force one), then cut over the records.
- ASUS router still does its thing (updating asuscomm.com); requires no change there.

### Solution B — Delegated `_acme-challenge` subzone (canonical "ACME CNAME delegation")

Decouple ACME from DDNS at the DNS layer rather than the architecture layer.

**Changes:**
1. Create a new zone authoritative for `_acme-challenge.ai-servicers.com`. Two options:
   - Sub-zone on Cloudflare itself (e.g., `acme.ai-servicers.com`) with its own NS delegation.
   - Dedicated zone at a free ACME-friendly provider like `deSEC.io` (explicitly supports DNS-01 delegation).
2. Add NS records in `ai-servicers.com`: `_acme-challenge.ai-servicers.com NS <new zone>`.
3. Configure Traefik with a second DNS provider for the new zone (lego supports multiple resolvers).
4. Wildcard CNAME unchanged; everything else unchanged.

**Why architecturally clean:**
- Concerns separated: DDNS owns `*.ai-servicers.com`, ACME owns `_acme-challenge.ai-servicers.com`.
- Wildcard CNAME's behavior no longer matters for ACME — the subzone delegation pre-empts it.
- New services need no DNS edit (wildcard still covers them) AND no ACME placeholder (subzone delegation handles it).

**Risks / costs:**
- Second DNS provider/zone to maintain.
- Second API credential to issue and rotate.
- More moving parts; more places to misconfigure.
- Doesn't fix the architectural smell of the DDNS chain itself — the chain still routes via `asuscomm.com`, which means a third-party DNS zone is in the resolution path for normal traffic. (Acceptable, perhaps; just doesn't get fixed.)

### Solution C — Pre-populate explicit `_acme-challenge.<host>` placeholders (rejected as architectural)

Add an explicit non-CNAME record at each `_acme-challenge.<host>.ai-servicers.com` to pre-empt the wildcard for that name. Initially 3 records (apex+wildcard, registry.gitlab, diagrams.nginx).

**Why rejected:**
- Treats a structural collision as a per-record patch.
- Operational sharp edge: every new cert host requires remembering to add a placeholder. Forgotten placeholders surface as cert-renewal failures days later.
- Solves the immediate symptom but leaves the underlying DDNS-via-CNAME architecture in place.

Acceptable as a 30-minute emergency patch if cert deadlines force action before any architectural change can land. Not acceptable as the steady-state design.

### Solution D — Drop the wildcard, write per-service explicit A records (rejected on cost)

Replace `*.ai-servicers.com CNAME embracenow.asuscomm.com` with N explicit A records (one per service), maintained by an updater.

**Why rejected vs Solution A:**
- Strictly more work: N records to update on every IP change vs 1 (the apex). Same daemon; more API calls; more pages of config.
- No architectural advantage over A: both are "Cloudflare-managed A records via API." A is simply A's special case where the apex is the only A record and a same-zone CNAME wildcard inherits.

---

## 4. Recommendation

**Solution A.**

Justifications:
- Single source of truth for the residential IP (apex A in Cloudflare).
- Zone is self-contained; no foreign zone in any resolution path.
- ACME works as a side effect of the architecture being right, not as a bolt-on.
- Lowest operational sharp-edge: zero per-service DNS work for new services.
- Reversible: if the updater is removed and the user wants to go back to ASUS DDNS, switch the apex from A back to CNAME → embracenow.asuscomm.com. Wildcard CNAME-to-apex stays. The "DDNS via CF API" subsystem can be deleted without otherwise touching the zone.

**Implementation order, time-aware:**

Given the 3-day deadline on `registry.gitlab.ai-servicers.com` and the 7-day deadline on the wildcard, I would propose:

1. **Hour 0** — Deploy DDNS updater container against the apex A. Verify the apex A is live and matches current external IP.
2. **Hour 0–1** — Switch wildcard CNAME from `embracenow.asuscomm.com` → `ai-servicers.com`. Verify name resolution from external (DNS propagation: <5 min on Cloudflare).
3. **Hour 1** — Remove `mailu` CNAME if redundant, or leave (no impact).
4. **Hour 1–2** — Force re-issuance of the 3-day-deadline cert (`registry.gitlab`) by removing its entry from `acme.json` and restarting Traefik. Verify clean renewal.
5. **Hour 2** — Force re-issuance of remaining failing certs.
6. **Day 1** — Drop standalone `open-webui` cert (consolidation step from earlier plan; covered by wildcard via SNI).
7. **Day 1–2** — Documentation: update `traefik/CLAUDE.md` and `docs/context/operations.md` (or scaffold via `/context-save init` if absent) with the new DDNS architecture. Postmortem captures the lego-version-change hypothesis.

Total clock time to safety: ~2 hours of active work; total to clean steady state: ~1 day.

---

## 5. Questions for the Review Board

1. **Is Solution A the architecturally correct choice?** If not, what's the alternative the analysis missed? Specifically: is delegation (Solution B) more correct because it preserves "ASUS owns DDNS, Cloudflare owns ACME" as a clean separation of providers?

2. **Is there a hidden risk in Solution A** I haven't surfaced? Examples I've considered and discarded but want a second pass on:
   - DNSSEC interaction with apex CNAME → A change (zone is not DNSSEC-signed today; verified).
   - Cloudflare proxy mode on apex (currently proxied: true; A record can also be proxied).
   - CF API rate limits on the DDNS updater (residential IP changes rarely; well within CF's 1200/5min).
   - SPF/DKIM/DMARC: do any reference the apex CNAME chain in a way that would break? (SPF references `a:mail.ai-servicers.com`, not the apex; DKIM/DMARC are TXT, unaffected.)

3. **Is the implementation order safe**? Specifically the order: deploy updater → cut over wildcard target → renew certs. Any reordering or precaution that should land first?

4. **Is the lego-version-change hypothesis worth verifying** before declaring root cause closed? Or is the architectural fix the right move regardless of when the symptom appeared?

5. **Anything in the broader project context** (this is a multi-service homelab with ~78 containers, Traefik fronting all public services, mail server in the mix) that this proposal would damage and that an outsider would notice but I'd miss because I'm too close?

---

## 6. Reference

- `/home/administrator/projects/traefik/docs/acme-renewal-2026-05-08/PLAN.md` — the **original** plan, now superseded by this document. Kept for history because it documents the wrong-turn reasoning before the wildcard finding.
- `/home/administrator/projects/traefik/docs/acme-renewal-2026-05-08/cf-acme-records-before.json` — empty array (no explicit `_acme-challenge` records exist).
- `/home/administrator/projects/traefik/docs/acme-renewal-2026-05-08/cf-all-records-raw.json` — full Cloudflare zone snapshot.
- `/home/administrator/projects/traefik/acme.json.bak-2026-05-08` — pre-change cert backup (still valid; nothing has been changed yet on the cert side).
- `projects/traefik/CLAUDE.md` — current Traefik project state, including the entry under "Open Issues" describing the ACME failure (added today).
- `projects/CLAUDE.md` — master index showing the broader infrastructure.
