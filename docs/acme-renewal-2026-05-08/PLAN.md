# ACME Renewal Remediation + DNS Architecture Fix — Execution Plan v2

**Date:** 2026-05-08 (revised after review board)
**Owner:** administrator (with Claude assistance)
**Status:** Draft — awaiting approval to start Phase 0
**Supersedes:** the v1 plan (originally proposed deleting `_acme-challenge` records that turned out not to exist; abandoned after wildcard-CNAME finding) and the SITUATION-AND-RECOMMENDATION.md draft (originally proposed `*.ai-servicers.com → ai-servicers.com` apex; rejected by reviewers due to Cloudflare proxy inheritance / mail risk).
**Source of architecture decisions:** [`docs/reviews/acme-ddns-arch-collision.final.md`](../reviews/acme-ddns-arch-collision.final.md) (Codex + Claude reviews; Gemini node failed).

---

## 1. Locked-in decisions (from review synthesis)

1. **Solution A (Cloudflare-API DDNS) is the architectural fix.** Solution B (delegated `_acme-challenge` subzone) explicitly rejected as a layered patch on a misdesigned DDNS plane.
2. **Wildcard target = `home.ai-servicers.com`** (a dedicated DNS-only A record), **not** the apex. Avoids Cloudflare proxy inheritance through CNAME chain (proxied apex would pull mail through the CF proxy and break SMTP/IMAP).
3. **`mail.ai-servicers.com` becomes an explicit DNS-only record** before any wildcard change. Currently load-bearing via wildcard synthesis.
4. **Apex CNAME → A change is decoupled** from the ACME unblock. Done in a separate phase, after renewals stabilize.
5. **DDNS updater = `qdm12/ddns-updater`** (actively maintained, exposes Prometheus metrics, slots into existing Grafana stack). `oznu/cloudflare-ddns` rejected (archived/unmaintained).
6. **Separate, scoped Cloudflare API token** for DDNS updater. Do not reuse the lego token. Scope: Zone:DNS:Edit on `ai-servicers.com` only.
7. **Stopgap Solution C executes first** as a 15-minute emergency patch. Stub TXT records remove the cert-renewal deadline pressure. Architecture proceeds on a calendar timeline, not the May 11 cert expiry.
8. **Internal NAT-reflection / DNS hairpin testing** is mandatory after wildcard cutover. ASUS Merlin's DNS director may stop rewriting `mail.ai-servicers.com` to LAN IPs once the wildcard no longer chains through `embracenow.asuscomm.com`.
9. **DDNS updater observability is mandatory** before declaring done. qdm12 Prometheus metrics → existing Grafana with stale-update > 15 min alert.
10. **TTL pre-lowering** is a separate step at T-24h, not part of the cutover itself.

---

## 2. Cert inventory + consolidation decisions

| Cert | Expires | Days | Decision |
|---|---|---:|---|
| `registry.gitlab.ai-servicers.com` | 2026-05-11 | 3 | **Keep standalone**, renew via stopgap (Phase 0) |
| `ai-servicers.com` + `*.ai-servicers.com` | 2026-05-15 | 7 | **Keep wildcard**, renew via stopgap (Phase 0) |
| `open-webui.ai-servicers.com` | 2026-05-15 | 7 | **Consolidate** to wildcard in Phase 7 (covered by SNI) |
| `diagrams.nginx.ai-servicers.com` | 2026-06-03 | 26 | **Keep standalone**, renew via stopgap (Phase 0) |

---

## 3. Execution phases

Each phase: goal → steps → exit criterion → rollback. Approval mode: full-auto after Phase 0 sign-off (per user direction); pause if any verification step shows unexpected state.

### Phase 0 — Emergency stopgap (TODAY, ~15 minutes)

**Goal:** unblock all currently-failing renewals so cert deadlines stop driving the architectural timeline.

**Why this works:** an explicit non-CNAME record at `_acme-challenge.<host>.ai-servicers.com` pre-empts the wildcard synthesis for that exact name. lego's SOA walk for that name then terminates at `ai-servicers.com SOA` (Cloudflare's NS). lego's CF provider finds the zone, writes its real validation TXT alongside the stub (CF allows multiple TXTs at one name), challenge passes, cert issues.

**Steps:**

1. Create 4 stub TXT records via Cloudflare API:
   - `_acme-challenge.ai-servicers.com TXT "stub-pre-empt-wildcard"` (covers apex + wildcard cert)
   - `_acme-challenge.registry.gitlab.ai-servicers.com TXT "stub-pre-empt-wildcard"`
   - `_acme-challenge.diagrams.nginx.ai-servicers.com TXT "stub-pre-empt-wildcard"`
   - `_acme-challenge.open-webui.ai-servicers.com TXT "stub-pre-empt-wildcard"` *(harmless to keep through Phase 7; removed in Phase 5)*
2. Verify each: `dig +short SOA _acme-challenge.<name>.ai-servicers.com @1.1.1.1` should return `dell.ns.cloudflare.com…`, **not** anything from `asuscomm.com`.
3. Force-renew `registry.gitlab.ai-servicers.com` (3-day deadline first):
   - `docker stop traefik`
   - `jq 'del(.letsencrypt.Certificates[] | select(.domain.main == "registry.gitlab.ai-servicers.com"))' acme.json > acme.json.tmp && mv acme.json.tmp acme.json`
   - Confirm permissions (`chmod 600 acme.json`)
   - `docker start traefik`
   - Watch: `docker logs traefik --since 1m -f | grep -iE 'acme|registry.gitlab'`
   - Expect "Server responded with a certificate" within ~3 minutes (DNS-01 + 60s `delayBeforeCheck` + LE issuance).
4. Verify: `echo | openssl s_client -connect registry.gitlab.ai-servicers.com:443 -servername registry.gitlab.ai-servicers.com 2>/dev/null | openssl x509 -noout -dates` shows `notBefore` of today.
5. Repeat steps 3–4 for `ai-servicers.com` (apex+wildcard cert) and `diagrams.nginx.ai-servicers.com`. **Skip `open-webui`** — Phase 7 will consolidate it.

**Exit criterion:** 3 reissued certs with `notBefore` of today; Traefik logs free of "failed to find zone asuscomm.com" for those domains.

**Rollback:** restore `acme.json.bak-2026-05-08` (already exists from earlier today); delete the stub TXT records via CF API. Total cost ~30s.

---

### Phase 1 — Pre-cutover prep (T-24h before Phase 4)

**Goal:** reduce DNS cache surprises and surface hardcoded references before they cause silent breakage.

**Steps:**

1. Lower TTL on `ai-servicers.com` (apex CNAME), `*.ai-servicers.com` (wildcard CNAME), and any other DDNS-relevant records to 60s (or "Auto"). Via CF API.
2. `grep -rn 'embracenow\|asuscomm' /home/administrator/projects/ 2>/dev/null` — find any hardcoded references in scripts, configs, monitoring tools, backup configs. Fix or document each. Save output to `docs/acme-renewal-2026-05-08/embracenow-references.txt`.
3. Inventory `mail.ai-servicers.com` consumers: which containers/configs reference it. Save to `docs/acme-renewal-2026-05-08/mail-consumers.txt`. Particular attention to:
   - Nextcloud's mail integration (uses hosts-file workaround per `traefik/CLAUDE.md`)
   - Mailserver's own client connections
   - Any cron jobs / monitoring that hits SMTP/IMAP
4. Inventory current Cloudflare zone state: re-snapshot `cf-all-records-raw.json` → `cf-all-records-pre-cutover.json` (timestamped).

**Exit criterion:** all artifacts written; no surprises in the embracenow grep.

**Rollback:** TTL increase is reversible via CF API. Read-only otherwise.

---

### Phase 2 — DDNS infrastructure (T-0 to T-1h)

**Goal:** stand up the DDNS updater against a single new record (`home.ai-servicers.com`) without touching any existing record. Establish observability.

**Steps:**

1. **Mint new CF API token:** Cloudflare dashboard → My Profile → API Tokens → Create Token. Template: "Edit zone DNS." Restrict to zone `ai-servicers.com`. Name: `ddns-updater`. Save to `$HOME/projects/secrets/ddns-updater.env` as `CF_DNS_API_TOKEN_DDNS=<token>`. `chmod 600`.
2. **Create initial `home.ai-servicers.com` A record** via CF API: A `<current-residential-IP>`, TTL 60, `proxied: false`. (Initial IP can be looked up via `dig +short embracenow.asuscomm.com @1.1.1.1`.)
3. **Deploy `qdm12/ddns-updater`** in `projects/ddns-updater/`:
   - Create directory + `docker-compose.yml` referencing `qmcgaw/ddns-updater:latest` (or pinned tag).
   - Config (`config.json` mounted into container) maintains 1 record initially: `home.ai-servicers.com` A, `proxied: false`, provider=cloudflare, token from env.
   - `restart: unless-stopped`.
   - Network: connect to existing `traefik-net` for outbound HTTPS; no inbound exposure required.
   - Promtail will auto-discover logs.
4. **Bring up:** `cd projects/ddns-updater && docker compose up -d`. Watch one update cycle.
5. **Verify:** the updater's first push should be a no-op (record already matches current IP). `docker logs ddns-updater` should show success.
6. **Wire observability:**
   - Add Prometheus scrape target for qdm12 metrics endpoint (port 8000 by default; expose internally on `traefik-net` only).
   - Grafana dashboard: simple panel showing last-update timestamp + current IP.
   - Alert: "ddns-updater stale" if `time() - dns_updater_last_success > 900` (15 min).

**Exit criterion:** updater operational; `home.ai-servicers.com` resolves externally to current IP; Grafana shows fresh updates; alert is not firing.

**Rollback:** `docker compose down` in `projects/ddns-updater/`; delete `home.ai-servicers.com` record via CF API. ASUS DDNS still owns everything else; nothing changes.

---

### Phase 3 — Make `mail.ai-servicers.com` explicit (T-1h to T-1h15)

**Goal:** decouple mail flow from the wildcard before any wildcard change touches it.

**Steps:**

1. Decide proxy posture for mail. **Default: `proxied: false`** — mail does not work through CF's standard proxy.
2. Via CF API, create `mail.ai-servicers.com` A `<residential-IP>`, `proxied: false`, TTL 60. (Same value as `home.ai-servicers.com`. Use a CNAME → `home.ai-servicers.com` if preferred for single-source-of-truth-on-IP; either works.)
3. Optionally: add `mail.ai-servicers.com` to the qdm12 config so it's auto-updated alongside `home`. (If using CNAME → home, this is unnecessary.)
4. Verify external resolution returns the residential IP (not CF anycast):
   ```
   dig +short mail.ai-servicers.com @1.1.1.1
   ```
5. **Smoke-test mail flow:**
   - SMTP submission from a known client (Nextcloud's outbound mail integration) — verify a test message delivers.
   - IMAP from a mail client — verify connection works.
6. **Side-todo (optional):** SPF check. With explicit `mail.ai-servicers.com` proxied:false, `a:mail.ai-servicers.com` in SPF should now return the residential IP. Confirm with `spfquery` or `dig TXT ai-servicers.com` + manual interpretation.

**Exit criterion:** `mail.ai-servicers.com` resolves to residential IP externally; mail clients work; no errors in mailserver logs.

**Rollback:** delete the explicit `mail.ai-servicers.com` record. Wildcard synthesis takes over again (current state).

---

### Phase 4 — Wildcard cutover — the actual architectural fix (T-1h15 to T-2h)

**Goal:** stop the wildcard chain from leaving the `ai-servicers.com` zone. ACME unblocks as a side effect.

**Steps:**

1. Via CF API, change `*.ai-servicers.com` from CNAME → `embracenow.asuscomm.com` to CNAME → `home.ai-servicers.com`. Keep `proxied: false` (current state). TTL 60.
2. Verify external resolution (chain stays in zone):
   ```
   dig <something-undefined>.ai-servicers.com @1.1.1.1
   ```
   Should return `home.ai-servicers.com` → `<residential-IP>`. Chain ends in zone.
3. Verify SOA walk for ACME:
   ```
   dig SOA _acme-challenge.test-fix.ai-servicers.com @1.1.1.1
   ```
   Authority section should be `ai-servicers.com SOA`, **not** `asuscomm.com SOA`.
4. **CRITICAL: internal NAT-reflection / hairpin test.** From inside a container on `traefik-net`:
   ```bash
   docker run --rm --network traefik-net alpine sh -c \
     'apk add --no-cache bind-tools netcat-openbsd >/dev/null 2>&1 && \
      echo "=== mail.ai-servicers.com from inside container ==="; \
      getent hosts mail.ai-servicers.com; \
      echo "=== SMTP submission probe ==="; \
      nc -zv mail.ai-servicers.com 587 2>&1; \
      echo "=== IMAPS probe ==="; \
      nc -zv mail.ai-servicers.com 993 2>&1'
   ```
   - **If `mail.ai-servicers.com` resolves to LAN IP** (router DNS director still rewriting): mail flow internal-to-LAN unchanged. Continue.
   - **If it resolves to public IP and connects work:** router supports loopback NAT. Continue.
   - **If it resolves to public IP and connects fail:** NAT loopback broken. Mitigation: extend the existing Docker hosts-file workaround (per `traefik/CLAUDE.md`, mailserver was already mapped to 172.22.0.17 internally) to any newly-affected service. Don't proceed until this is resolved.
5. Smoke-test Nextcloud → mailserver flow: Nextcloud admin panel → "Send test email" or trigger any flow that goes through Nextcloud's mail config.

**Exit criterion:** wildcard resolution stays in zone; lego SOA walk lands on `ai-servicers.com`; internal mail flow verified working.

**Rollback:** flip the wildcard CNAME back to `embracenow.asuscomm.com` via CF API. Stub TXTs from Phase 0 are still in place, so renewals continue working in any state. Total rollback cost: ~30s + 60s TTL propagation.

---

### Phase 5 — Drop the stopgap (T-2h to T-2h15)

**Goal:** prove the architecture works without the safety net; remove operational footgun (stub TXTs that look mysterious to future-you).

**Steps:**

1. Delete the 4 stub TXT records from Phase 0 via CF API.
2. Force-renew the wildcard cert as a smoke test (no stubs in place):
   - Stop Traefik, jq-edit `acme.json` to remove `ai-servicers.com` cert entry, start Traefik.
   - Watch logs.
   - Expect clean issuance.
3. Verify with `openssl s_client` that `notBefore` is fresh.

**Exit criterion:** wildcard cert reissued without stub assistance.

**Rollback:** re-add stub TXTs (revert to Phase 0 state). The architecture still works either way; stubs are belt-and-suspenders.

---

### Phase 6 — (Decoupled, optional) Apex record-type change

**Goal:** make the apex A-record-managed-by-updater rather than a CNAME-flattened record from `embracenow.asuscomm.com`. Removes the third-party zone from the apex resolution path entirely.

**Timing:** at least one week after Phase 5. After renewals have soaked, after the DDNS updater has survived at least one real residential IP change cycle, OR after manually verifying the updater handles a forced IP change correctly.

**Steps:**

1. Add apex `ai-servicers.com` to qdm12 config: A record, `proxied: true` (preserves current externally-observable behavior — CF anycast IPs returned).
2. Atomic CF API transaction: delete apex CNAME, create apex A `<residential-IP>` `proxied: true`. (CF API doesn't allow A and CNAME at same name simultaneously, so this is delete+create. Use a single batch request if available, otherwise delete then create as quickly as possible.)
3. Verify external behavior unchanged: `https://ai-servicers.com` still serves the same content with the same cert.
4. ASUS DDNS becomes vestigial. **Leave enabled** as redundancy until at least one real IP change is observed working through the CF updater. Document the cutoff date.

**Exit criterion:** apex is A-record managed by the updater; CF zone now fully self-contained for IP propagation.

**Rollback:** delete apex A, restore apex CNAME → `embracenow.asuscomm.com`. ASUS DDNS chain reactivates immediately.

---

### Phase 7 — Consolidate `open-webui` to wildcard

**Goal:** drop the redundant standalone cert; let the wildcard cover via SNI.

**Steps:**

1. Locate the labels on the `open-webui` container that ask for a per-host cert. Likely `traefik.http.routers.open-webui.tls.certresolver=letsencrypt`.
2. Drop the `tls.certresolver` label (preferred) OR add explicit `tls.domains[0].main=ai-servicers.com` + `tls.domains[0].sans=*.ai-servicers.com` to pin the wildcard.
3. Re-deploy via the open-webui project's `deploy.sh`.
4. Stop Traefik, jq-edit `acme.json` to remove `open-webui.ai-servicers.com` cert entry, start Traefik.
5. Verify: browser test of `https://open-webui.ai-servicers.com` shows the wildcard cert (subject `CN=ai-servicers.com`, SAN includes `*.ai-servicers.com`).
6. Soak for ~24h. Confirm Traefik does not attempt to issue a new standalone cert.

**Exit criterion:** open-webui served by wildcard; no standalone open-webui cert in `acme.json`; no renewal attempts in logs.

**Rollback:** revert label change in open-webui's deploy script, re-deploy. Traefik re-issues standalone cert (works now that ACME is unblocked).

---

### Phase 8 — Documentation + postmortem

**Goal:** capture the architectural decision and the operational learnings for future-you and the next person debugging an analogous issue.

**Steps:**

1. **Update `projects/traefik/CLAUDE.md`:**
   - Move ACME entry from "Open Issues" → "Resolved Issues" with: structural collision name, the `home.ai-servicers.com` design, qdm12 updater operational notes.
   - Add a **DDNS architecture** subsection documenting the `home.ai-servicers.com` pattern, the separate scoped CF token, the rollback path (apex CNAME → embracenow as break-glass).
2. **Scaffold or update `docs/context/operations.md`** with:
   - Cloudflare zone shape (apex, wildcard, home, mail).
   - Token inventory: lego token (zone DNS edit), DDNS-updater token (zone DNS edit, separately rotatable).
   - DDNS update flow.
3. **Write `docs/acme-renewal-2026-05-08/POSTMORTEM.md`:**
   - Original symptom (renewal failures after Traefik 3.4 → 3.6 bump).
   - Root cause (structural collision, not stale config).
   - Wrong turns documented honestly (v1 plan thought records existed; v2 SITUATION-AND-RECOMMENDATION recommended wildcard→apex; review board caught the mail-via-proxy risk).
   - Correct architecture and why.
   - Hairpin / NAT-reflection caveat.
   - lego version bump as proximate trigger; not the root cause.
4. **Test gap notes:** none — no source code changed in this work.

**Exit criterion:** docs reflect the new state; review board file references are stable and findable.

---

## 4. Combined risk register (from review board synthesis)

| Risk | Phase | Severity | Mitigation |
|---|---|---|---|
| Mail breaks via CF proxy inheritance if wildcard→apex | 4 | **High** | Use `home.ai-servicers.com` (DNS-only) as wildcard target. Decision locked in §1.2. |
| Internal NAT-reflection rewrite stops covering `*.ai-servicers.com`; Nextcloud→mailserver may break | 4 | **High** | Mandatory hairpin test from inside a container. §3 Phase 4 step 4. |
| DDNS updater silent failure delays cert renewal until next 60-day window | 2, ongoing | Medium | qdm12 Prometheus metrics → Grafana alert on stale > 15 min. §3 Phase 2 step 6. |
| Hardcoded `embracenow`/`asuscomm` references in scripts/configs | 1 | Medium | `grep -rn` sweep. §3 Phase 1 step 2. |
| Pre-existing SPF flaw (CF proxy = anycast IPs in `a:mail` lookup) | 3 | Medium | Side-todo: explicit `mail.ai-servicers.com` proxied:false fixes this as a side effect. §3 Phase 3 step 6. |
| Reusing lego CF token for DDNS conflates rotation timelines | 2 | Low | Mint separate scoped token. Decision locked in §1.6. |
| Stale-cache window during ISP IP changes | ongoing | Low | TTL 60s; pre-lowered 24h before cutover. §3 Phase 1 step 1. |
| Cert reissuance during debugging burns LE rate-limit quota | 0, 5, 7 | Low | Stop Traefik before each acme.json edit; don't loop-restart. |
| AAAA records published unintentionally if updater misconfigured | 2 | Low | Explicitly disable AAAA in qdm12 config. |
| LE rate limits during force-renew of 4 certs | 0 | Low | 4 issuances << CF's 50/week cap. |

---

## 5. Artifacts produced

- `docs/acme-renewal-2026-05-08/PLAN.md` — this file (canonical execution doc)
- `docs/acme-renewal-2026-05-08/SITUATION-AND-RECOMMENDATION.md` — initial recommendation (now superseded; preserved for context)
- `docs/acme-renewal-2026-05-08/cf-all-records-raw.json` — Cloudflare zone snapshot pre-fix
- `docs/acme-renewal-2026-05-08/cf-acme-records-before.json` — empty (proves no explicit `_acme-challenge` records existed)
- `docs/acme-renewal-2026-05-08/embracenow-references.txt` — Phase 1 grep output
- `docs/acme-renewal-2026-05-08/mail-consumers.txt` — Phase 1 inventory
- `docs/acme-renewal-2026-05-08/cf-all-records-pre-cutover.json` — re-snapshot at T-24h
- `docs/acme-renewal-2026-05-08/POSTMORTEM.md` — Phase 8 deliverable
- `acme.json.bak-2026-05-08` — pre-Phase-0 backup (already exists)
- `projects/ddns-updater/` — new project directory (Phase 2)
- `$HOME/projects/secrets/ddns-updater.env` — separate scoped CF token (Phase 2)

---

## 6. Pre-flight checklist

- [ ] Confirm: Solution A with `home.ai-servicers.com` target (not apex) is approved
- [ ] Confirm: stopgap (Phase 0) executes today, before any architectural change
- [ ] Confirm: `qdm12/ddns-updater` is acceptable; alternative is `timothymiller/cloudflare-ddns`
- [ ] Confirm: separate scoped CF token will be minted manually (browser session needed)
- [ ] Confirm: review-board Gemini node failure is logged separately (not part of this work)
- [ ] Approval mode: full-auto after Phase 0 — pause only on verification mismatches
