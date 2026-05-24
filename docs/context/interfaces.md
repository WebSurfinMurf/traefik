# Interfaces

## Entry Points (host ports)
| Port | Name | Protocol | Purpose |
|---|---|---|---|
| 80 | web | HTTP | Plain HTTP (mostly redirects to HTTPS) |
| 443 | websecure | HTTPS | All public web services |
| 25 | smtp | TCP | Incoming mail |
| 465 | smtps | TCP | SMTP over SSL (deprecated but supported) |
| 587 | submission | TCP | Mail client submission |
| 993 | imaps | TCP | IMAP over SSL |
| 8083 | traefik | HTTP | Dashboard + API |
| 9100 | metrics | HTTP | Prometheus metrics |

## Cert Resolver
- Name: `letsencrypt`
- Storage: `/etc/traefik/acme.json` (host: `projects/traefik/acme.json`, chmod 600)
- Challenge: DNS-01 via Cloudflare (`delayBeforeCheck: 60`)
- Backup directive: `httpChallenge` entrypoint set to `web` (fallback)

## Cert Dump
- Format: `projects/data/traefik-certs/<domain>/certificate.crt` + `privatekey.key`
- Consumers: non-Traefik services that need TLS certs (mailserver, etc.)
- Updated on `acme.json` change by the sidecar

## Traefik API
- Internal: `http://localhost:8083/api/...` (dashboard via `dashboard@internal`, also exposed at `traefik.ai-servicers.com`)
- Common queries: `/api/http/routers`, `/api/http/middlewares`, `/api/http/services`, `/api/tcp/routers`, `/api/version`

## Label Schema (per-service)
Required for HTTP service discovery:
```
traefik.enable=true
traefik.docker.network=traefik-net
traefik.http.routers.<name>.rule=Host(`<host>`)
traefik.http.routers.<name>.entrypoints=websecure
traefik.http.routers.<name>.tls=true
traefik.http.routers.<name>.tls.certresolver=letsencrypt
traefik.http.services.<name>.loadbalancer.server.port=<port>
```

Multi-service container (e.g., GitLab + Registry) must explicitly bind router→service:
```
traefik.http.routers.<name>.service=<service-name>
```

TCP service (e.g., mail) variant:
```
traefik.tcp.routers.<name>.rule=HostSNI(`*`)
traefik.tcp.routers.<name>.entrypoints=<imaps|smtps|smtp|submission>
traefik.tcp.routers.<name>.service=<service-name>
traefik.tcp.services.<service-name>.loadbalancer.server.port=<port>
```

## Middlewares (file-defined)
- `keycloak-auth@file` — forwardauth middleware for services that gate behind Keycloak
- File-defined routers (always loaded): `acme-challenge-router@file`, `redirect-router@file`, `homepage-router@file`, `nginx-livekit-debug@file`

## Internal Routers (always present)
- `api@internal`, `dashboard@internal`, `prometheus@internal`

## Cloudflare zone shape (`ai-servicers.com`)

Records load-bearing for this project's operation:

| Name | Type | Content | Proxied | Maintained by | Purpose |
|---|---|---|---|---|---|
| `ai-servicers.com` (apex) | A | residential IP | true | `projects/ddns-updater` | Apex resolution; CF returns anycast IPs to clients |
| `*.ai-servicers.com` (wildcard) | CNAME | `home.ai-servicers.com` | false | manual | All undefined names resolve via in-zone chain |
| `home.ai-servicers.com` | A | residential IP | false | `projects/ddns-updater` | In-zone DDNS target; wildcard's CNAME terminator |
| `mail.ai-servicers.com` | A | residential IP | false | `projects/ddns-updater` | Explicit mail record (DNS-only, bypasses CF proxy) |

Hard rules:
- The wildcard CNAME target **must stay in-zone** (or ACME DNS-01 breaks for every cert).
- Apex MUST NOT be `proxied=false` if mail flow goes through wildcard inheritance — but since mail is explicit, apex proxy state is decoupled from mail.
- Any new explicit `mail.<provider>` etc. records that need to bypass CF proxy must be added explicitly with `proxied=false`.
