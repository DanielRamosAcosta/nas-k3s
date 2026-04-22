---
id: NASKS-52
title: >-
  Migrate photos.danielramos.me to Cloudflare gray cloud with Let's Encrypt
  DNS-01
status: In Progress
assignee: []
created_date: '2026-04-22 17:59'
updated_date: '2026-04-22 18:02'
labels:
  - infra
  - traefik
  - immich
  - tls
  - refined
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

Immich (`photos.danielramos.me`) is currently proxied by Cloudflare (orange cloud). On the Cloudflare Free plan, proxied traffic is capped at **100 MB per request**. Daniel's father tried to upload ~200 photos + videos from a trip; only 5 appeared. Loki logs (22-apr, 15:06–15:17 local) show repeated `FileUploadInterceptor: Request error while uploading file, cleaning up` + `ECONNRESET` — uploads being aborted mid-transfer, consistent with Cloudflare cutting requests that exceed the 100 MB threshold. 4K videos from the trip trip this limit; normal photos (5–10 MB) go through fine, which matches the "5 visible out of 200" symptom.

Options evaluated and discarded:
- **Cloudflare Tunnel** — verified via Immich Discussion #13175 and Cloudflare Community that tunnels are also capped at 100 MB on Free plan; the limit is per plan, not per entry mechanism.
- **Tailscale** — rejected by Daniel, too much ops burden for an elderly family user (his father).
- **Oracle Cloud Always Free** — rejected as fragile: ARM capacity is a lottery, accounts terminated without notice, card required.
- **Hetzner CX23 (€5.43/mo)** — rejected as not worth the monthly cost for this scope.
- **Upgrade Cloudflare Pro (200 MB)** — still too small for 4K video.
- **Split-horizon DNS / Tailscale per-device** — doesn't solve "uploads from outside the home" which is the actual use case (Daniel himself lives abroad).

Chosen path: **expose Immich directly (DNS-only, gray cloud)**. Risk posture accepted given Authelia is already deployed as OIDC provider (no forwardAuth middleware on Immich yet — follow-up) and homelab is single-tenant.

## Design decisions (resolved via /grill-me interview)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Scope: only `photos.danielramos.me`** | YAGNI. Validate with one service before considering wider gray migration. Other services stay on Cloudflare Origin Cert via existing TLSStore default. |
| 2 | **ACME challenge: DNS-01** (not HTTP-01) | Doesn't depend on port 80 reachability. DNS is already on Cloudflare, API token is trivial. Supports wildcards if ever needed. |
| 3 | **Cert scope: specific for `photos.danielramos.me`** (not wildcard) | YAGNI, single service. Easier to rotate/revoke. Wildcard compromised = whole zone compromised. |
| 4 | **`acme.json` persistence: hostPath `/data/traefik/acme`** | Matches repo pattern (`/data/*`). Avoids burning LE rate limit on Traefik restarts. Cost-free. |
| 5 | **CF API token: new dedicated** (not reusing cloudflare-ddns token) | Least privilege per purpose. If rotated independently, doesn't break ACME. Better audit trail in CF logs. |
| 6 | **ACME email: `danielramosacosta1@gmail.com`** | Personal email is fine; not exposed in Certificate Transparency logs (only SANs are). Alias indirection = YAGNI for one cert. |
| 7 | **LE endpoint: production directly** (no staging) | Single cert, mature flow, rate limit (5 duplicate certs/week) is hard to hit. Staging iteration = 2x work for no gain here. |
| 8 | **Router ports: 80 + 443** (already open) | Redirect HTTP→HTTPS works from internet. Apps mostly go to HTTPS directly anyway; redirect covers the "padre teclea sin https" edge case. |
| 9 | **Rate limit: same PR as migration** | Gray cloud + no WAF = brute-force risk against Immich's `/api/auth/login`. Same logical change, should ship together. |
| 10 | **Rate limit scope: only `/api/auth/*`** (average=2, burst=5) | Global limit would hit legitimate app usage (thumbnails, upload chunks). Targeted limit attacks the real risk (login brute force). |
| 11 | **IngressRoute helper strategy: extend `ingressRoute.from()`** with optional `certResolver` and `extraRoutes` params | Keeps call site terse in `immich.libsonnet`. Backward compatible (new params default to null/[]). |
| 12 | **Rollout: single PR with all repo changes, then manual CF dashboard toggle** | Simplicity. Accept ~10–30s of TLS errors for orange-proxy consumers while Traefik fetches the first LE cert (CF strict mode would see self-signed during that window). |
| 13 | **Timing: immediately** (not wait for night) | Dad is already broken (can't upload). Short downtime &lt; current indefinite breakage. Rollback to orange is instant if something goes worse. |

## Explicitly NOT in scope for this task (follow-ups)

- Authelia `forwardAuth` middleware in front of Immich (separate PR, UX-impacting)
- Crowdsec bouncer plugin on Traefik (follow-up task)
- Geo-blocking (Spain only) — wait until there's evidence of abuse in Traefik logs
- Migrating other services to gray cloud — re-evaluate after photos runs for a month

## Implementation plan

### File changes (all in one PR)

1. **`lib/system/traefik/traefik.libsonnet`**
   - Add `certificatesResolvers.letsencrypt` via `additionalArguments`:
     - email = `danielramosacosta1@gmail.com`
     - storage = `/data/acme.json`
     - dnschallenge = true
     - dnschallenge.provider = `cloudflare`
   - Add `env: [{ name: 'CF_DNS_API_TOKEN', valueFrom: { secretKeyRef } }]` pointing to new SealedSecret
   - Enable `persistence` in the chart values (hostPath-backed volume on `/data/traefik`)
   - Keep existing TLSStore default (`cloudflare-origin-cert`) — other services still use it

2. **`lib/system/traefik/traefik.secrets.json`**
   - Add `cfDnsApiToken` with the sealed value (already sealed, stored outside the repo during planning)

3. **`lib/utils/ingressRoute.libsonnet`**
   - Extend `from()` signature: `from(service, hostOrMap, middlewares=[], certResolver=null, extraRoutes=[])`
   - If `certResolver != null`: render `tls.certResolver` instead of `tls.store`
   - If `extraRoutes` non-empty: append each route object (with its own `match`, `middlewares`) to `spec.routes`

4. **`lib/media/immich/immich.libsonnet`**
   - Define `authRateLimit` middleware (traefik.io/v1alpha1 Middleware kind, RateLimit: average=2, burst=5)
   - Change `ingress_route: u.ingressRoute.from(self.service, 'photos.danielramos.me', [], 'letsencrypt', [extraRouteForAuthPath])`
   - Extra route matches `Host(photos.danielramos.me) && PathPrefix(/api/auth)` with `middlewares=[authRateLimit]`

### Deploy steps

1. Commit + push all 4 file changes in a single commit on `main`
2. CI exports manifests to `manifests` branch
3. Wait for ArgoCD to detect (webhook-driven, near instant)
4. Sync `traefik` and `immich` apps manually from ArgoCD UI (or `argocd app sync`)
5. Watch Traefik logs via Grafana/Loki for: `Register... Configuration` / `Obtained certificate` for `photos.danielramos.me`
6. Validate externally with `curl -v https://photos.danielramos.me --resolve photos.danielramos.me:443:&lt;public-IP&gt;` — expect LE cert in the chain
7. Cloudflare dashboard → DNS → `photos` record → toggle orange 🟠 → gray ☁️
8. Verify father can upload (wait for him to retry)

### Rollback plan

- **If cert emission fails** (DNS-01 errors, token wrong scope, etc.): revert the PR commit. Traefik goes back to TLSStore default with CF Origin cert. No data loss.
- **If gray cloud exposes something unexpected** (unexpected abuse, attacks): toggle 🟠 back in CF dashboard. Takes effect within minutes (CF DNS TTL). Rate limit + Immich login remain as defense in depth.
- **If Traefik crashes on startup** due to config error: `kubectl rollout undo deployment/traefik -n system` as emergency. SealedSecret and code changes can be reverted in a follow-up commit.

## Security notes

- CF API token scope: `Zone:DNS:Edit` on `danielramos.me` only — confirmed during token creation via playwright agent
- Token is **strict-scoped SealedSecret** bound to namespace `system` + name `traefik-cf-dns-api-token` — cannot be decrypted elsewhere
- Port 80 on host listens only on Traefik, which redirects to 443 (no plaintext content served)
- Immich login (its internal auth) + rate limit on `/api/auth` = two layers against brute force
- IP of the NAS (current dynamic, managed by `cloudflare-ddns`) becomes publicly resolvable once gray. Accepted risk for the single-tenant homelab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Traefik deployment has `CF_DNS_API_TOKEN` env var populated from the new `traefik-cf-dns-api-token` SealedSecret
- [ ] #2 Traefik persistence enabled with hostPath `/data/traefik` mounted at `/data`
- [ ] #3 Traefik `additionalArguments` include the letsencrypt ACME resolver (DNS-01, cloudflare provider, email `danielramosacosta1@gmail.com`, storage `/data/acme.json`)
- [ ] #4 `lib/utils/ingressRoute.libsonnet` helper `from()` extended with optional `certResolver` and `extraRoutes` params, backward compatible with all existing callers
- [ ] #5 Immich IngressRoute uses `certResolver='letsencrypt'` and declares an extra route for `PathPrefix(/api/auth)` with the new `authRateLimit` middleware (Traefik RateLimit, average=2, burst=5)
- [ ] #6 `tk eval environments/media` compiles without errors
- [ ] #7 `tk eval environments/system` compiles without errors
- [ ] #8 Commit pushed to main; CI-generated manifests branch updated
- [ ] #9 ArgoCD sync of `traefik` and `immich` apps completes green
- [ ] #10 External `curl --resolve photos.danielramos.me:443:<public-ip>` shows a Let's Encrypt-issued certificate (issuer contains 'Let's Encrypt' or 'R3'/'E1' etc.)
- [ ] #11 Cloudflare DNS record `photos` toggled to DNS-only (gray cloud)
- [ ] #12 Father confirms he can upload videos &gt;100 MB from outside the home network
<!-- AC:END -->
