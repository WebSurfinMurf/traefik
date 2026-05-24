---
name: acme-ddns-arch-collision
created: 2026-05-08
status: review-complete
sources: [codex, claude]
gemini_status: failed_node_config
---

# DNS architecture collision — synthesized review outcome

**Review board participation:** 2 of 3 nodes (Codex, Claude). Gemini node failed at the verify step due to a `GEMINI_CLI_TRUST_WORKSPACE` env-config issue in its container — not a transient failure. Synthesis is 2-of-3, but reviewers' analyses largely converged.

---

## Consensus (both Codex and Claude agree)

1. **Diagnosis is correct.** The SOA-walk-via-wildcard-CNAME analysis is the actual root cause. The error wording ("failed to find zone asuscomm.com") only occurs through this path. Not a stale-config issue, not a token-scope issue, not transient. **Structural.**

2. **Solution A is right; Solution B is not "more architecturally correct."** B preserves a third-party zone (`asuscomm.com`) in the resolution path for normal traffic. That's the actual smell. Decoupling ACME via delegation routes around the smell rather than fixing it. (Claude: "B's 'clean separation of providers' framing dignifies an accident as an architecture.")

3. **Original plan's DDNS updater choice is wrong.** Skip `oznu/cloudflare-ddns` — repo archived, last release ~2020. Use **`qdm12/ddns-updater`** (Go, actively maintained, multi-provider, exposes Prometheus metrics) or `timothymiller/cloudflare-ddns` (Python, CF-only, simpler).

4. **Mail flow is the highest-risk area.** `mail.ai-servicers.com` is currently load-bearing via the wildcard CNAME. Any wildcard change can break it. Must be made an **explicit DNS-only record** before the wildcard cutover.

5. **Lower TTLs 24h before cutover** as a separate step. Don't conflate with the cutover itself.

6. **lego-version-bump verification is not blocking.** Note in postmortem; don't gate the fix on it. Architecture is wrong regardless.

7. **`registry.gitlab` 3-day deadline should not drive architecture timing.** (Both reviewers, framed differently — Claude explicitly recommends Solution C stopgap; Codex implicitly via "defer apex change until after renewals are healthy.")

---

## Key insights

### From Codex (the one I'd most likely have shipped without)

- **(Codex) Cloudflare proxy inheritance through CNAME chains will break mail.** If any node in a CNAME chain has `proxied: true`, the whole chain is treated as proxied. Currently apex is `proxied: true` and wildcard is `proxied: false`. If we naively `*` → `ai-servicers.com` (apex), wildcard names get pulled through the proxy. Mail (SMTP/IMAP) doesn't work through CF's standard proxy. **Mail clients break.**

- **(Codex) `mail.ai-servicers.com` is currently load-bearing via wildcard.** The original brief mentioned `mailu.ai-servicers.com` (an explicit CNAME record); the actually-used hostname per `traefik/CLAUDE.md` is `mail.ai-servicers.com`, which is implicit (synthesized via wildcard). Make it explicit *before* anything wildcard-related.

- **(Codex) Don't point wildcard at apex.** Use a dedicated same-zone DDNS target: `home.ai-servicers.com A <residential IP> proxied=false`. Then `*` CNAME → `home.ai-servicers.com` and `mail` CNAME (or A) → `home.ai-servicers.com`. Avoids the proxy-inheritance trap entirely.

- **(Codex) Apex CNAME → A change is not required to restore ACME.** It's an additional architectural cleanup. Stage it separately from the urgent ACME unblock to reduce cutover risk. CF API doesn't allow A and CNAME at the same name simultaneously, so it's a delete/create transition either way.

- **(Codex) Pre-existing SPF flaw.** SPF references `a:mail.ai-servicers.com`. With wildcard chaining through proxied apex, `mail.ai-servicers.com` resolves to CF anycast IPs. SPF `a:` checker sees CF IPs, not the actual MTA → SPF fails today. DKIM presumably saves outbound mail. Not Solution A's fault but worth a side-todo.

### From Claude (independent / fresh-context)

- **(Claude) Internal NAT reflection / DNS hairpin is the highest-likelihood unintended consequence.** ASUS Merlin's DNS director rewrites lookups of `embracenow.asuscomm.com` to LAN IPs (existing project workaround for Docker → mailserver). Currently this rewrite *transitively* covers `mail.ai-servicers.com` via the wildcard chain. After Solution A, the wildcard no longer chains through embracenow → ASUS DNS director may stop rewriting → containers may try to resolve `mail.ai-servicers.com` to public IP and hairpin-NAT through router. May silently break Nextcloud → mailserver. **Test from inside a container before declaring done.**

- **(Claude) Stopgap C is the correct emergency response.** 15 minutes of work: add 4 stub TXT records at `_acme-challenge.<each cert host>.ai-servicers.com TXT "stub"`. The explicit non-CNAME records pre-empt the wildcard. lego SOA walks for those names terminate at `ai-servicers.com SOA`. Renewals succeed. **Buys 90 days, removes deadline pressure from architecture.** Author originally rejected C but only as steady-state — Claude correctly points out it's the right *stopgap*.

- **(Claude) Mint a separate, record-scoped CF token for the DDNS updater.** Don't reuse the lego token. Least privilege; separable rotation; compromise of one doesn't bleed into the other.

- **(Claude) The DDNS updater is a new SPOF.** Wire qdm12's Prometheus metrics to existing Grafana stack. Alert on stale-update > 15 min. Keep ASUS DDNS enabled as break-glass fallback through at least one real IP-change cycle.

- **(Claude) Hidden references to `embracenow` or `asuscomm` may exist elsewhere.** `grep -r embracenow projects/` and `grep -r asuscomm projects/` before cutover. Scripts, monitoring, backups can silently break.

- **(Claude) Apex CNAME also poisons the SOA walk** even without the wildcard. Solution A removes both poisoning records, not just one. Worth understanding when explaining the fix.

---

## Disagreements

### D1: Wildcard target — apex (Claude) vs dedicated DDNS hostname (Codex)

- **Claude:** `*` → `ai-servicers.com` (apex) is fine; CF flattens/proxies behavior is identical externally; one less record.
- **Codex:** Don't do this. CF proxy inheritance + the proxied-apex / DNS-only-wildcard mismatch can pull mail (and other DNS-only services) through the CF proxy. **Use a dedicated `home.ai-servicers.com` A record (DNS-only) as the DDNS target, then CNAME both `*` and `mail` to it.**

**My read:** Codex wins this one. Cost of being wrong with the dedicated-target approach: one extra A record (trivial). Cost of being wrong with the wildcard→apex approach: mail flow breaks during cutover, in production, for an unknown duration. The conservative engineering choice is the explicit dedicated DDNS target. Take Codex's pattern.

### D2: When to change apex CNAME → A

- **Codex:** Defer the apex record-type change until *after* renewals are healthy. It's architectural cleanup, not the urgent ACME unblock. Decouple them.
- **Claude:** Order is: lower TTLs → DDNS updater up → apex CNAME → A first → wildcard CNAME → in-zone second. Both as part of the same cutover.

**My read:** Codex's decoupling is the safer staging. Both reach the same end state, but Codex's order means the ACME-restoring change (wildcard→home.ai-servicers.com) stands on its own and is reversible. The apex CNAME→A change can land later as a separate, observable change. Take Codex's staging.

### D3: How to interpret the user's "architecturally correct" preference

- **Codex:** Implicit — solve the structural problem with minimum risk surface. Stage changes; explicit records over wildcard inheritance.
- **Claude:** Explicit — "architecturally correct" doesn't mean "do architecture under deadline pressure." Stopgap-then-fix *is* the correct sequence.

**My read:** Both right, complementary. Claude names the meta-principle explicitly; Codex enacts it. Combined: stopgap C now (15 min), then proper architecture on a calendar.

---

## Synthesized action plan (revised, replaces SITUATION-AND-RECOMMENDATION.md plan)

### Phase 0 — Emergency stopgap (today, 15 minutes)
1. Via CF API, create 4 stub TXT records:
   - `_acme-challenge.ai-servicers.com TXT "stub"` (covers apex + wildcard cert renewal)
   - `_acme-challenge.registry.gitlab.ai-servicers.com TXT "stub"` (3-day deadline)
   - `_acme-challenge.diagrams.nginx.ai-servicers.com TXT "stub"`
   - `_acme-challenge.open-webui.ai-servicers.com TXT "stub"` (will become redundant after consolidation; harmless to keep)
2. Force-renew `registry.gitlab` cert: stop Traefik, jq-edit `acme.json` to remove that cert entry, start Traefik. Watch logs.
3. Force-renew apex+wildcard cert similarly.
4. Force-renew `diagrams.nginx`. Skip `open-webui` (will be consolidated in Phase 7).
5. Verify with `openssl s_client` for fresh `notBefore` on all 3 reissued certs.

**Exit:** all certs renewed for 90 days. Cert deadline pressure removed.

### Phase 1 — Pre-cutover prep (T-24h before Phase 4)
1. Lower TTL on apex `ai-servicers.com` and wildcard `*.ai-servicers.com` from current to 60s (or "Auto").
2. `grep -rn 'embracenow\|asuscomm' /home/administrator/projects/` — find any hardcoded references. Fix or note.
3. Inventory current `mail.ai-servicers.com` usage: which containers/configs reference it; which expect it to resolve to LAN IP via NAT-reflection rewrite.

### Phase 2 — DDNS infrastructure
1. Mint a new Cloudflare API token, scoped: **Zone:DNS:Edit on `ai-servicers.com` only**. Name: `ddns-updater`. Store in `$HOME/projects/secrets/ddns-updater.env`.
2. Deploy `qdm12/ddns-updater` as a Docker Compose service in `projects/ddns-updater/`. Config: maintain `home.ai-servicers.com` A record only initially. `proxied: false`.
3. Verify it pushes the current external IP correctly. Watch one cycle.
4. Wire its Prometheus metrics to the existing Grafana stack. Add alert: "DDNS updater stale > 15 min."

**Exit:** updater operational against one record; observability in place.

### Phase 3 — Make mail explicit
1. Via CF API, add `mail.ai-servicers.com` A `<residential-IP>`, `proxied: false`, TTL 60. (Manual entry; can later be moved into ddns-updater config so it tracks IP changes alongside `home`.)
2. Verify external resolution returns residential IP, not CF anycast.
3. Verify mail clients (Nextcloud's mail integration, any IMAP/SMTP clients) still connect correctly.
4. Side-todo (optional): SPF check (`spfquery` or similar) — confirm `a:mail.ai-servicers.com` now passes for your real mail-sending IP, not CF anycast. Pre-existing issue surfaced but not blocking.

**Exit:** mail flow on explicit record, decoupled from wildcard.

### Phase 4 — Cutover wildcard (the actual ACME architectural fix)
1. Change `*.ai-servicers.com` CNAME target from `embracenow.asuscomm.com` to `home.ai-servicers.com`. Keep `proxied: false` (current state).
2. Verify external resolution: `dig <something>.ai-servicers.com` returns `home.ai-servicers.com` → residential IP. SOA chain stays inside `ai-servicers.com`.
3. Verify lego SOA walk: `dig SOA _acme-challenge.test.ai-servicers.com @1.1.1.1` should return `ai-servicers.com SOA`, not `asuscomm.com SOA`.
4. **Critical test from inside a container on `traefik-net`:**
   ```
   docker run --rm --network traefik-net alpine sh -c \
     'apk add --no-cache bind-tools >/dev/null && \
      getent hosts mail.ai-servicers.com && \
      nc -zv mail.ai-servicers.com 587'
   ```
   Verify the result matches expected behavior. If `mail.ai-servicers.com` no longer resolves to a LAN IP and the connect fails, the hosts-file workaround needs to expand or internal DNS overrides need to be added.

**Exit:** wildcard resolution stays in zone; ACME works without stub TXTs; internal services unbroken.

### Phase 5 — Drop the stopgap
1. Remove the 4 stub TXT records added in Phase 0.
2. Force-renew one cert as a smoke test (e.g., the wildcard) without stubs in place — confirms the architectural fix actually works as a side effect.

### Phase 6 — (Decoupled, optional) Apex record-type change
After Phase 5 has soaked for at least one week and renewals are stable:
1. Add apex `ai-servicers.com` to ddns-updater's managed records (`proxied: true`).
2. Via CF API, atomically: delete apex CNAME, create apex A `<residential-IP>` `proxied: true`. Updater now owns it.
3. Verify external behavior unchanged (CF anycast IPs returned to public).
4. ASUS DDNS becomes vestigial. Leave enabled as redundancy until at least one real IP change is observed working through the CF updater.

### Phase 7 — Consolidate `open-webui` to wildcard (per original plan)
1. Adjust open-webui Traefik labels to drop `tls.certresolver` (rely on wildcard SNI matching).
2. Re-deploy.
3. Remove `open-webui.ai-servicers.com` cert from `acme.json`. Verify Traefik does not re-issue.

### Phase 8 — Documentation + postmortem
1. Update `projects/traefik/CLAUDE.md`: move ACME entry from Open Issues → Resolved Issues with the proper architectural fix.
2. Update or scaffold `docs/context/operations.md` with new DDNS architecture.
3. Write `docs/acme-renewal-2026-05-08/POSTMORTEM.md` capturing: structural collision, what was tried, why Solution A's first-draft variant (wildcard→apex) was wrong, why dedicated `home.ai-servicers.com` is right, lego version bump as proximate trigger, ASUS DNS-director hairpin caveat.

---

## Risks flagged (combined from both reviewers)

| Risk | Severity | Mitigation |
|---|---|---|
| Mail breaks via CF proxy inheritance if wildcard→apex | **High** | Use dedicated `home.ai-servicers.com` target instead. (Codex) |
| Internal NAT-reflection rewrite stops covering `*.ai-servicers.com` after wildcard cutover; Nextcloud→mailserver may break | **High** | Test from inside container before declaring Phase 4 done. Expand hosts-file workaround if needed. (Claude) |
| DDNS updater silent failure delays cert renewal until next 60-day window | Medium | Wire qdm12 Prometheus metrics to Grafana with stale-update alert. (Claude) |
| Hardcoded `embracenow.asuscomm.com` references in scripts/configs | Medium | `grep -r` before cutover. (Claude) |
| Pre-existing SPF flaw (CF proxy = anycast IPs in `a:mail` lookup) | Medium | Side todo: explicit `mail.ai-servicers.com` proxied:false, then SPF passes. (Codex) |
| Reusing lego CF token for DDNS conflates rotation timelines and blast radii | Low | Mint separate scoped token. (Claude) |
| Stale-cache window during ISP IP changes | Low | Pre-lower TTLs to 60s 24h ahead of cutover. (Both) |
| Cert reissuance during debugging burns LE rate-limit quota | Low | Stop Traefik before each acme.json edit; don't loop-restart. (Claude) |
| AAAA records published unintentionally if updater misconfigured | Low | Explicitly disable AAAA in qdm12 config. (Codex) |
| LE rate limits during force-renew of 4 certs | Low | 4 issuances << CF's 50/week cap. (Claude) |

---

## What changed from the original recommendation

| Original | Revised |
|---|---|
| `*.ai-servicers.com → ai-servicers.com` (apex) | `*.ai-servicers.com → home.ai-servicers.com` (dedicated DDNS target) |
| Apex CNAME → A as part of the same cutover | Apex CNAME → A deferred to later phase, decoupled |
| `mailu.ai-servicers.com` as the mail concern | `mail.ai-servicers.com` (the actually-used name) — must be explicit before wildcard change |
| `oznu/cloudflare-ddns` suggested | `qdm12/ddns-updater` (oznu is archived/unmaintained) |
| Reuse existing CF token | Mint new scoped token for DDNS updater |
| Solution C ("placeholders") rejected as architectural | Solution C used as **stopgap** to remove deadline pressure; architecture proceeds on calendar |
| TTL lowering implicit | Explicit pre-cutover step at T-24h |
| No internal-DNS hairpin testing | Required Phase 4 verification step from inside a container |
| No DDNS updater observability | Required Phase 2 step: Grafana alert on stale update |
| No `grep -r embracenow/asuscomm` | Required Phase 1 step |
