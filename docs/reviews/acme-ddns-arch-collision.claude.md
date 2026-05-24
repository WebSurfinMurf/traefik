---
source: claude
reviewed: 2026-05-08
context: acme-ddns-arch-collision.md
---

I've read the review brief and the Traefik CLAUDE.md. Here's my analysis.

---

## (1) Diagnosis assessment

**The SOA-walk-via-wildcard-CNAME diagnosis holds up.** lego's `dns01.FindZoneByFqdn` issues SOA queries up the label hierarchy. Cloudflare's wildcard is a CNAME (which RFC-style applies to all qtypes when no more-specific record exists), so a SOA query for `_acme-challenge.<host>.ai-servicers.com` is answered with the synthesized CNAME → `embracenow.asuscomm.com`, the recursive resolver chases it, gets a NOERROR with `asuscomm.com SOA` in authority, and lego concludes the zone is `asuscomm.com`. The error message ("failed to find zone asuscomm.com") matches exactly — there's no other path that produces that specific zone name. If it were a token-scope or CF-API issue, you'd see a 401/403 or "zone not authorized." It's structural.

**Alternative root cause the author didn't articulate but is worth naming:** the apex CNAME (`ai-servicers.com → embracenow`) on its own would also poison the SOA walk even if the wildcard didn't exist, because lego strips labels until it hits the apex. So Solution A's apex CNAME → A change is doing more architectural work than the brief makes obvious — it's not just enabling the wildcard fix, it's removing the second SOA-poisoning record. Worth saying explicitly.

**One other thing the diagnosis underweights:** lego has had a `LEGO_EXPERIMENTAL_CNAME_SUPPORT` flag and various follow-CNAME tweaks across versions. The 3.4 → 3.6 Traefik bump *did* update the bundled lego, and that absolutely could have flipped the precise SOA-walk behavior. Don't rule it out as a contributing factor — but don't chase it either; the architecture is wrong regardless.

---

## (2) Solution A vs Solution B

**Solution A is correct. Solution B is not "more architecturally correct" — it is a layered patch on a misdesigned DDNS plane.** Argue this back when defending the design:

- B preserves a third-party zone (`asuscomm.com`) in the resolution path for *every* normal request. That's the actual smell. Decoupling ACME doesn't fix it; it just routes around it.
- B's "clean separation of providers" framing is appealing but false — it's separation of *concerns by accident of failure*, not by design intent. The DDNS plane being CNAME-chained into a foreign zone wasn't an architectural choice, it was an artifact of using the router's built-in DDNS client. Don't dignify the accident.
- B adds a second zone, second credential, and second failure mode (delegated zone outage breaks ACME). A removes a failure mode (foreign zone outage breaks everything).
- B is the right answer when you *cannot* push to your DNS provider via API. You can. So it's not.
- The only thing B preserves that A loses: ASUS DDNS as the source-of-truth for the residential IP. That's a feature you don't want — you want CF apex A as source of truth, single API, single credential.

A is right. Defend it.

---

## (3) Specific suggestions

**DDNS-updater choice:** Skip `oznu/cloudflare-ddns` — last meaningful release ~2020, effectively unmaintained. Pick **`qmcgaw/ddns-updater`** (Go, actively maintained, multi-provider, has Prometheus metrics endpoint — useful given your Grafana stack) or **`timothymiller/cloudflare-ddns`** if you want CF-only and Python. I'd take qmcgaw because it slots into your observability stack without extra work.

**Token scope:** Don't reuse the lego token. Mint a separate API token, scoped to **a single zone DNS edit on `ai-servicers.com` only**, named `ddns-updater`. Least privilege, separable rotation, and the kill-switch case (DDNS updater compromised) doesn't bleed into ACME. CF's token templates support this directly.

**TTL/proxied/CNAME-flattening details:**

- **Lower TTLs 24h before cutover.** Current "Auto" on proxied records is 300s, but downstream resolvers may have it cached longer. Set apex and wildcard to TTL 60 *now*, then come back tomorrow to change records. Don't conflate this with the cutover.
- **Keep `proxied: true` on the apex A.** This matches current externally-observable behavior (CF anycast IPs returned, residential IP hidden). Several DDNS updaters default `proxied: false` — check the config explicitly. qmcgaw exposes this as a per-record flag.
- **CNAME flattening at apex becomes irrelevant** once apex is A. Externally-observable: identical (CF proxied returns CF IPs either way). Internally: CF no longer has to resolve `embracenow.asuscomm.com` at every query, slight latency win.
- **`*` → CNAME → `ai-servicers.com`** is fine; CF will follow the in-zone CNAME at edge for proxied records and serve A directly. For DNS-only names (none in your zone today), clients chase the CNAME. Either way, lego's SOA walk now terminates inside `ai-servicers.com`. ACME unblocks.
- **Cutover sequence — important ordering nit the brief gets subtly wrong:** the brief lists "deploy updater → switch wildcard target." But you must change the **apex from CNAME to A first**, *then* change the wildcard from `→ embracenow` to `→ ai-servicers.com`. If you flip the wildcard first while the apex is still a CNAME to embracenow, the wildcard chains CNAME-to-CNAME-to-asuscomm and you've changed nothing. Order: lower TTLs (T-24h) → bring up DDNS updater in dry-run/observe mode → updater takes over apex A → verify external dig matches → flip wildcard to in-zone CNAME → verify → force renewals.

**Stopgap recommendation the brief understates:** for the 3-day `registry.gitlab` deadline, **execute Solution C right now as a 15-minute stopgap**, *separate from* Solution A. Add explicit `_acme-challenge.registry.gitlab.ai-servicers.com TXT "stub"`, `_acme-challenge.ai-servicers.com TXT "stub"`, `_acme-challenge.open-webui... TXT "stub"`, `_acme-challenge.diagrams.nginx... TXT "stub"`. Any non-CNAME record at the exact name pre-empts the wildcard for that name. Lego's SOA walk for those names then terminates at `ai-servicers.com SOA`. Renewals succeed. You buy 90 days. Then do Solution A on a calendar timeline, not a deadline timeline. **Don't let cert deadlines drive an architectural change.** The brief considers C as "acceptable as 30-min emergency patch only" but stops short of recommending it *in addition to* A. Do both.

---

## (4) Risks and gotchas

**Internal NAT reflection / DNS hairpin (the big one the author missed).** Per the project CLAUDE.md, ASUS Merlin's DNS director currently rewrites lookups of the ASUS DDNS hostname (`embracenow.asuscomm.com`) to LAN IPs as a hairpin workaround. Because the wildcard CNAMEs into `embracenow.asuscomm.com`, this rewrite *transitively* applies to `mail.ai-servicers.com` and friends today (which is why you have the Docker hosts-file workaround for Nextcloud → mailserver). After Solution A, the wildcard no longer chains through `embracenow.asuscomm.com`. ASUS's DNS director may **stop rewriting** internal lookups of `*.ai-servicers.com`, which means containers might suddenly resolve `mail.ai-servicers.com` to the public IP and try to hairpin-NAT through the router. That may work (if router supports loopback NAT) or break (most ASUS+Merlin do, but quirks). **Test before declaring done:** from inside a container on `traefik-net`, `getent hosts mail.ai-servicers.com` and try a connect. If it breaks, the hosts-file workaround needs to expand to more services, or you need internal DNS overrides.

**SPF + CF proxy interaction (preexisting, not Solution A's fault, but flag it).** Your SPF `a:mail.ai-servicers.com` resolves through the wildcard CNAME → CF proxy (proxied=true) → CF anycast IPs. Outbound mail leaves from your residential IP. Receivers checking SPF resolve `mail.ai-servicers.com` to CF IPs and don't find your residential IP among them → **SPF fails today, before any change**. DKIM presumably saves you. Solution A doesn't fix this and doesn't make it worse, but you should note it on a side todo. If you want to fix: add an explicit `mail.ai-servicers.com A <residential-IP> proxied=false` record (DDNS updater would also manage this) and SPF passes. That's a separate change.

**Cloudflare proxy mode at apex with A vs CNAME-flattened.** Externally: identical (CF returns CF anycast IPs in both cases when proxied=true). Internally at CF edge: A is simpler — no CNAME-flattening recursion to a foreign zone every TTL. Slight latency win. Behavioral change zero from the public's POV.

**MX, DKIM CNAMEs, DMARC, brevo/sendgrid:** all explicit non-wildcard records, all pre-empt the wildcard, all unchanged by Solution A. ✓ The author's analysis here is correct.

**DDNS-updater death = new SPOF.** If updater dies and IP changes, apex A goes stale, all services unreachable until human fixes. Mitigations: (a) `restart: unless-stopped`, (b) Grafana alert: `cf_apex_a_record != dig +short embracenow.asuscomm.com` for >15 min, (c) keep ASUS DDNS enabled as a manual fallback (flip apex back to CNAME → embracenow as the break-glass), (d) qmcgaw exposes Prometheus metrics so wire it to your existing observability stack.

**LE rate limits during forced re-issue:** 5 duplicate certs per week per exact set, 50 per registered domain per week. Re-issuing 4 certs is well within. But don't loop-restart Traefik during debugging — each removed `acme.json` entry burns an issuance.

**`acme.json` corruption during forced re-issue:** stop Traefik → cp -a acme.json acme.json.bak → jq edit → start Traefik. Don't edit while Traefik is running.

**CF token scope:** existing token (zone-edit on `ai-servicers.com`) is sufficient for everything proposed in A — A-record management, wildcard CNAME edits, ACME TXT writes. Nothing else needed. But create a *separate* DDNS token (least-privilege) rather than reuse. Two tokens, distinct rotation schedules.

**Propagation timing:** the "<5min CF propagation" claim is true at CF authoritative; downstream resolvers cache to TTL. With current 300s TTLs, full propagation is ~10min worst case at public resolvers. Pre-lowering TTL to 60s a day before cuts that to ~2min.

---

## (5) Blind spots a same-context reviewer would miss

1. **The internal NAT reflection cascade above.** Author wrote the Nextcloud workaround themselves, knows it intimately, but wouldn't connect it to the wildcard cutover unless prompted. Highest-likelihood unintended-consequence in the whole change.
2. **Conflating emergency with architecture.** Author has a 3-day deadline and is solving it with the architectural fix. Wrong tool. Stopgap with C, then schedule A. The decision-style note ("architecturally correct over easy") doesn't mean "do architecture under deadline pressure" — it means "when given a choice, prefer correct." Stopgap-then-fix *is* the correct sequence.
3. **DDNS observability.** No mention of how you'd notice if the updater silently stops working until cert renewal fails 60 days out. Wire it into your existing Grafana/Loki/Promtail before declaring done — you have the stack.
4. **Token rotation hygiene.** Reusing the lego token for DDNS conflates two rotation timelines and two blast radii. Author wouldn't think of it because the token is "already there and works."
5. **`embracenow.asuscomm.com` may be hardcoded somewhere.** Worth a `grep -r embracenow projects/` before cutover. If anything else references it (a script, a backup tool, an internal hosts file), it'll silently break.
6. **The brief frames Solution B as an option but doesn't note that lego *also* supports per-record CNAME delegation** (`_acme-challenge.<host> CNAME _acme-challenge-<host>.delegated.tld`) which is a third variant of B that's lower-overhead than NS delegation. Still worse than A for the same architectural reasons, but the brief's B-vs-A comparison is slightly unfair to B by picking the heaviest variant. Doesn't change the conclusion.

---

## (6) Concrete answers to the 5 questions

**Q1 — Is A architecturally correct? Is B more correct?**
A is correct. B is not more correct. The "ASUS owns DDNS, CF owns ACME" framing dignifies an accident (router's built-in DDNS client) as an architecture (separation of providers). It isn't one. A makes the CF apex A the single source of truth for the residential IP, removes the foreign zone from every resolution path, and makes ACME work as a side effect of the zone being self-contained. That's the right shape.

**Q2 — Hidden risks?**
The five you listed (DNSSEC, proxy on apex A, CF rate limits, SPF anchor, MX independence) are correctly identified and correctly dismissed. Add: (a) internal DNS hairpin behavior may shift — test from inside containers; (b) DDNS updater is a new SPOF — wire to Grafana; (c) preserve `proxied: true` explicitly in updater config (some default to false); (d) use a separate, record-scoped CF token for the updater; (e) preexisting SPF-vs-CF-proxy issue surfaced by the analysis but not caused by A.

**Q3 — Implementation order safe?**
Mostly. Three corrections: (1) **lower TTLs 24h ahead**, separate from cutover; (2) flip **apex CNAME → A first**, then wildcard CNAME → in-zone — if you flip wildcard first while apex is still a CNAME to embracenow, you've changed nothing; (3) **execute Solution C as a stopgap immediately** (15 min, 4 stub TXTs) so cert deadlines stop driving the architectural timeline. Then do A on a calendar.

**Q4 — Verify lego version change?**
No. The architecture is wrong regardless. Note the version bump in the postmortem as the proximate trigger; don't make verification a gate on the fix.

**Q5 — Broader project context damage?**
Highest-risk: the **internal NAT reflection / hosts-file workaround** for `mail.ai-servicers.com` from Docker containers is implicitly load-bearing on the wildcard chaining through `embracenow.asuscomm.com`. After Solution A it may stop applying. Test internal mail flow from Nextcloud → mailserver after the wildcard flip. Lower-risk but worth scanning: any script, monitoring tool, or backup config that references `embracenow.asuscomm.com` or `asuscomm.com` directly. `grep -r embracenow ~/projects/` and `grep -r asuscomm ~/projects/` before cutover. The 78-container fleet is fine — Traefik labels don't care about DNS chains.

---

**Bottom line:** Solution A is right; defend it against the B framing. Sequence is: stub TXTs *now* (15 min, buys 90 days), TTL pre-lower today, DDNS updater up tomorrow with separate scoped token + Grafana alert, apex A flip, wildcard flip, force-renew. Test internal `mail.ai-servicers.com` resolution from a container post-flip — that's the highest-likelihood surprise.
