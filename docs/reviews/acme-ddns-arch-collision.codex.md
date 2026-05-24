---
source: codex
reviewed: 2026-05-08
context: acme-ddns-arch-collision.md
---

**Findings**
- Critical: Solution A as written can break mail resolution and SPF. The doc proposes `*.ai-servicers.com -> ai-servicers.com` and treats mail as unaffected. That is not safe. Your raw zone has apex `ai-servicers.com` `proxied: true` and wildcard `proxied: false`. Cloudflare documents that if any hostname in a CNAME chain is proxied, the request is treated as proxied, and mail protocols do not work through the standard proxy. Your SPF also explicitly authorizes `mail.ai-servicers.com`, not `mailu.ai-servicers.com`. If `mail.ai-servicers.com` falls through the wildcard to a proxied apex, SPF can authorize Cloudflare IPs instead of your MTA and IMAP/SMTP clients can break.
- High: Changing the apex from CNAME to A is not required to restore ACME, but it does add avoidable cutover risk. The proposed order couples the ACME fix to an apex record-type swap. Cloudflare's API rules do not allow A and CNAME on the same name simultaneously, so that step is inherently a delete/create transition. You can unblock renewals by making the wildcard resolve inside the Cloudflare-managed zone first and move the apex later.
- Medium: The doc focuses on `mailu.ai-servicers.com`, but the live project state says clients use `mail.ai-servicers.com` (per CLAUDE.md). That hostname is currently being carried implicitly by the wildcard. It needs an explicit record before any wildcard/proxy changes.

**Assessment**
The situation analysis is basically right: this is a structural collision, not a stale `_acme-challenge` cleanup issue. I agree with the direction of Solution A over delegation B for steady state. I do not agree with Solution A's exact record design.

What I would do differently: do not point the wildcard at the apex. Either:
1. Preferred: create a dedicated same-zone DDNS target such as `home.ai-servicers.com` or `edge.ai-servicers.com`, update that A record via Cloudflare API, point `*.ai-servicers.com` at that hostname, and make `mail.ai-servicers.com` an explicit DNS-only record to that same target.
2. Also acceptable: have the updater maintain a small fixed set of A records directly: `@`, `*`, and `mail`. That is not "N records per service"; it is 2-3 records total, and it avoids CNAME/proxy inheritance entirely.

**Specific suggestions**
- Do not use `oznu/cloudflare-ddns` as the default recommendation. Its GitHub repo is archived. Prefer `qdm12/ddns-updater` for a maintained multi-provider updater with health checks, or `timothymiller/cloudflare-ddns` if you want Cloudflare-only and simple multi-record config.
- Make `mail.ai-servicers.com` explicit and `DNS only` before touching the wildcard. If mail clients use `autodiscover` or `autoconfig`, make those explicit too.
- Keep wildcard proxy status aligned with intent. Today it is DNS-only. If you silently make wildcard names resolve through a proxied apex, you are doing an ACME fix and a Cloudflare traffic-path migration at the same time.
- TTL: for DNS-only A/CNAME records involved in the cutover, use `60` seconds or `Auto` if you want Cloudflare-managed low TTL. For proxied records, Cloudflare fixes TTL at 300 seconds. Do not assume "<5 min" means every resolver updates inside 5 minutes.
- Apex CNAME flattening: moving apex from CNAME to A does not matter for ACME once the wildcard stops leaving the zone. The real question is operational behavior, not flattening correctness. If you keep an apex CNAME, Cloudflare will flatten it at the apex anyway.

**Safer cutover**
1. Create `home.ai-servicers.com` A `108.35.80.85`, `DNS only`.
2. Bring up the updater against `home.ai-servicers.com` first and watch at least one no-op cycle.
3. Create `mail.ai-servicers.com` explicit `DNS only` A or CNAME to `home.ai-servicers.com`.
4. Change `*.ai-servicers.com` to point inside the zone. Keep it DNS-only initially unless you explicitly want all wildcard web traffic proxied.
5. Verify `_acme-challenge.test.ai-servicers.com` no longer resolves through `asuscomm.com`, and verify you can create/query a temporary TXT in Cloudflare.
6. Renew `registry.gitlab` first, then the wildcard cert.
7. Only after renewals are healthy, decide whether to move apex off ASUS DDNS. That change is architectural cleanup, not the urgent ACME unblock.
8. Leave ASUS DDNS enabled until the Cloudflare updater has survived at least one real IP change.

**Missing risks / gotchas**
- The doc's "SPF/DKIM/DMARC unaffected" claim is too broad. DKIM/DMARC are fine. SPF is not automatically fine because it keys off `mail.ai-servicers.com`.
- Residential IP changes still create a stale-cache window after the updater writes Cloudflare. DNS-only clients can continue using the old IP until TTL expiry. That matters more for mail clients and direct-origin subdomains than for proxied web traffic.
- If you publish AAAA later, manage it intentionally. Do not let an updater publish AAAA unless the homelab is actually reachable and filtered correctly over IPv6.
- Cloudflare batch DNS updates are not propagation-atomic. Avoid assuming a single bulk change eliminates all intermediate states.
- If you currently rely on direct source IP visibility for services under the wildcard, moving them behind Cloudflare changes logs, rate limiting, and origin ACL assumptions.

**Answers to the 5 questions**
1. Solution A's principle is correct. Delegation B is valid but not more correct for steady state. I would keep Cloudflare owning both DDNS and ACME for this zone, but I would not implement `wildcard -> proxied apex`.
2. Yes: the hidden risks are mail host/proxy/SPF breakage, accidental wildcard proxy-topology change, stale-cache behavior during ISP IP changes, and non-atomic record-type cutover at the apex.
3. The implementation order is not the safest version. Put explicit `mail.ai-servicers.com` and the same-zone DDNS target in place first, switch the wildcard second, renew third, and defer the apex record-type change until after certs are healthy.
4. The lego-version hypothesis is not worth blocking on. It may explain symptom timing, but it does not change the fix. Verify later only if you want a tighter postmortem.
5. The broader project risk is the mail path, not Traefik. With ~78 containers, the dangerous mistake is hiding a DNS/proxy behavior change inside the cert fix. Make the mail host explicit, keep wildcard behavior intentional, and stage the apex migration separately.

Sources: [Cloudflare proxy status](https://developers.cloudflare.com/dns/proxy-status/), [Cloudflare email troubleshooting](https://developers.cloudflare.com/dns/troubleshooting/email-issues/), [Cloudflare zone apex records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-zone-apex/), [Cloudflare batch DNS changes](https://developers.cloudflare.com/dns/manage-dns-records/how-to/batch-record-changes/), [Cloudflare DNS record API](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/), [qdm12/ddns-updater](https://github.com/qdm12/ddns-updater), [timothymiller/cloudflare-ddns](https://github.com/timothymiller/cloudflare-ddns), [oznu/docker-cloudflare-ddns](https://github.com/oznu/docker-cloudflare-ddns).
