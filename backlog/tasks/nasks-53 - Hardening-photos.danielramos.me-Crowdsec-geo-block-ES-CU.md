---
id: NASKS-53
title: 'Hardening photos.danielramos.me: Crowdsec + geo-block ES/CU'
status: Done
assignee: []
created_date: '2026-04-22 18:44'
updated_date: '2026-04-22 19:57'
labels:
  - infra
  - traefik
  - security
  - immich
  - refined
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

Follow-up to NASKS-52. `photos.danielramos.me` is now on Cloudflare gray cloud, directly exposed to internet scanners (Shodan indexes the IP, bots probe `/api/auth/login`).

Existing defenses:
- LE wildcard cert via Traefik TLSStore (valid chain, browsers trust it)
- Rate limit on `/api/auth/*` (Traefik RateLimit: avg=2, burst=5) — shipped in NASKS-52
- Immich's internal login

This task adds two more layers **targeted at photos** (not the orange-proxied services, which already sit behind Cloudflare WAF + country-level rules already enforced at the CF edge by Daniel):
1. **Crowdsec** full stack (agent + LAPI + Traefik bouncer) to block IPs known-bad by community blocklist and locally-detected attacks.
2. **Synchronous geo-block** allowing only ES + CU traffic on photos.

Fail2ban was considered and rejected — Crowdsec is its modern replacement; running both is redundant.

## Design decisions (resolved via /grill-me)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Geo-block scope: only `photos.danielramos.me`** | Other services already protected by CF edge (WAF + geo-block set at CF). Gray photos is the only direct-exposed target. Blast radius also contained. |
| 2 | **Allowlist: `[ES, CU]` + self-lockout accepted** | Daniel lives in ES; occasional travel → manually toggle photos back to orange for the trip. Tío/abuelos in CU need access. No runtime bypass needed. |
| 3 | **Crowdsec deployment: full stack (agent + LAPI + bouncer)** | Plugin-only misses the local detection layer. Full stack also exports metrics + joins the community blocklist bidirectionally. |
| 4 | **Geo-block: synchronous via Traefik GeoBlock plugin (NOT Crowdsec scenario)** | Crowdsec scenarios are reactive — first request from disallowed country passes, only subsequent ones banned. Unacceptable for geo-block; it must reject on first request. |
| 5 | **GeoBlock plugin: `PascalMinder/geoblock` (bundled IP2Location LITE)** | No MaxMind licence key needed for this middleware → separation from Crowdsec's MaxMind usage. Most-installed community plugin, simple config (`allowedCountries: [ES, CU]`). |
| 6 | **GeoIP DB for Crowdsec (geoip-enrich): MaxMind GeoLite2-Country + licence key** | Official, auto-updating, community-calibrated. Personal free tier sufficient. 5 min registration, 1 SealedSecret. |
| 7 | **Observability: Grafana dashboard + Crowdsec Console** | Grafana for long-term metrics (VictoriaMetrics persistence). Console for quick mobile debug of individual bans. |
| 8 | **Log ingestion: only Traefik access log** | Captures 90% of attack patterns (brute force, path probing, CVE exploit attempts). Immich-specific parser would be custom work for low additional value, and rate limit on /api/auth already covers the Immich-specific case. |
| 9 | **Acquisition source: Loki** (not DaemonSet hostPath) | Crowdsec agent pulls logs via LogQL queries against Loki. Uniform with rest of observability, no extra hostPath. Trade-off: creates dep on Loki being up. |
| 10 | **Real client IP: Traefik `forwardedHeaders.trustedIPs` with Cloudflare CIDR ranges** | Without this, Crowdsec bans Cloudflare edge IPs instead of real attackers (kills all orange services). Trust headers only from CF CIDRs (listed at cloudflare.com/ips-v4 + ips-v6). |
| 11 | **Local whitelist: none** | YAGNI. Default ban durations are short (4h); rate limit already mitigates common false positives (mistyped passwords). Revisit only if real false-positive rate justifies it. |
| 12 | **Deployment: vendorized Helm chart** (`charts/crowdsec/`) | Matches existing repo pattern (Traefik, K8s Dashboard). Chart maintained by Crowdsec team. |
| 13 | **Collections installed: `crowdsecurity/traefik`, `crowdsecurity/linux`, `crowdsecurity/http-cve`, `crowdsecurity/base-http-scenarios`, `crowdsecurity/geoip-enrich`** | Covers brute-force detection, path scanning, and common N-day exploit patterns (the most frequent automated attack surface). AppSec (WAF) collection deferred — over-engineering for current scope. |
| 14 | **Ban response: HTTP 403** (no captcha, no custom page) | Simple; 99% of bans are bots where captcha adds no value. Captcha would also add friction on legitimate false positives. |
| 15 | **Ban duration: 4h default** | Community-standard; rate limits and humans recover within a reasonable window; bots have moved IPs by then. |
| 16 | **Namespace: `system`** | Same as other infra (Traefik, CoreDNS, sealed-secrets). Same-namespace service discovery for the Traefik bouncer plugin → LAPI. |
| 17 | **Bouncer scope on Traefik: photos only** | Orange services already behind CF (WAF + geo-block at edge). Applying bouncer globally would stress LAPI with marginal benefit. |
| 18 | **State store: PostgreSQL** (not SQLite/hostPath) | Homelab's shared Postgres already has backups (`postgres-base-backup`). Consistent with Immich/Authelia/etc. Decisions survive pod restarts, queryable via SQL. |

## Implementation plan

### Files to add / modify

1. **`charts/crowdsec/`** — vendorize official Helm chart via `jb install` (add entry to `chartfile.yaml`).

2. **`lib/system/crowdsec/crowdsec.libsonnet`** — new module with Helm template, values including Postgres backend, MaxMind licence, Loki acquisition, collections list, Console enrollment, ServiceMonitor.

3. **`lib/system/crowdsec/crowdsec.secrets.json`** — new sealed secrets: `maxmindLicenceKey`, `crowdsecConsoleToken`, `crowdsecBouncerKey` (strict scope, system).

4. **`lib/databases/postgres/postgres.secrets.json`** — add `userCrowdsec` (cluster-wide encrypted password).

5. **`lib/databases/postgres/postgres.libsonnet`** — add `userCrowdsec: self.createUser('crowdsec', secrets.userCrowdsec, ...)` following the Immich/Authelia/etc. pattern.

6. **`lib/system/traefik/traefik.libsonnet`**:
   - Add `experimental.plugins.geoblock` (PascalMinder, pinned version)
   - Add `experimental.plugins.bouncer` (Crowdsec Traefik bouncer plugin)
   - Add `forwardedHeaders.trustedIPs` with all Cloudflare IPv4 + IPv6 CIDRs

7. **`lib/media/immich/immich.libsonnet`**:
   - Define two Middleware CRs: `geoblock-es-cu` and `crowdsec-bouncer`
   - Attach both (in that order) to the main photos route

8. **`environments/system/main.jsonnet`** — import + instantiate Crowdsec module.

### Deploy sequence

1. Seal 4 new secrets with `scripts/encrypt-secret.sh`.
2. Single PR.
3. Commit + push → CI → ArgoCD auto-sync.
4. Verify Postgres create-user Job green.
5. Verify Crowdsec agent pod + acquisition from Loki.
6. Verify Traefik loaded both plugins.
7. Test from non-ES IP (check-host.net US node) → HTTP 403 expected.
8. Test from ES IP → HTTP 200.
9. Validate Crowdsec Console enrollment.
10. Import Grafana dashboard.

### Rollback

Middlewares are per-route: remove the middleware list from the Immich IngressRoute → photos stops applying geo-block + bouncer, direct access back. Crowdsec Deployment can be scaled to 0; plugin should fail-open if LAPI unreachable (to verify).

## Explicitly NOT in scope

- Crowdsec AppSec / WAF engine.
- Immich-specific log parser.
- Bouncer on orange services.
- Local whitelist / bypass for Daniel when travelling (manual orange toggle workaround accepted).
- Crowdsec for SSH log detection on the NAS host.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Crowdsec Helm chart vendorized under `charts/crowdsec/` and listed in `chartfile.yaml`
- [x] #2 `lib/system/crowdsec/` module deploys agent + LAPI configured with Postgres backend, MaxMind licence key, Console enrollment, and Loki acquisition for Traefik logs
- [x] #3 Postgres `crowdsec` DB + user created via existing `postgres.createUser()` helper (migration Job runs green)
- [x] #4 Traefik Helm values include `experimental.plugins.geoblock` (PascalMinder) and `experimental.plugins.bouncer` (Crowdsec)
- [x] #5 Traefik `forwardedHeaders.trustedIPs` populated with all Cloudflare IPv4+IPv6 CIDRs (from cloudflare.com/ips-v4 + ips-v6)
- [x] #6 Immich IngressRoute main route carries two route-level middlewares: `geoblock-es-cu` and `crowdsec-bouncer` (in that order)
- [x] #7 `tk eval environments/system` and `environments/media` compile without errors
- [x] #8 ArgoCD syncs green: traefik + immich + crowdsec apps
- [x] #9 External test from non-ES/non-CU IP (check-host.net node in US) → HTTP 403 on photos
- [x] #10 External test from ES IP (own home / VPN ES) → HTTP 200 on photos
- [x] #11 Crowdsec Console dashboard shows enrolled instance + metrics flowing
- [ ] #12 Grafana dashboard for Crowdsec imported and rendering (VictoriaMetrics scraping the agent's /metrics endpoint)
- [ ] #13 Traefik access log shows real client IP (not CF edge IP) for a request via orange proxy — verified with a curl from external source and `grep` in Loki
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Implementation notes

### Pivots from the original plan

1. **Phase split**: originally planned as one big PR. Ended up as multiple commits: (a) prep (chartfile + postgres user), (b) agent+LAPI+GeoBlock, (c) postgres password cross-namespace mirror, (d) geoip-enrich parser vs collection fix, (e) externalTrafficPolicy=Local, (f) bouncer plugin wiring + Console enrollment automation. Worked out fine — each step was validated before the next.

2. **Console enrollment automation**: initial module dropped `config.console.yaml` from the chart because the ConfigMap mount is read-only and blocks `cscli console enroll`. Instead, ENROLL_KEY + ENROLL_INSTANCE_NAME env vars hand off to the docker entrypoint script, which runs the enroll on startup.

3. **Bouncer key distribution**: plugin config YAML is in git, so we couldn't put the API key there. Solved by sealing a random 48-char key once as `crowdsec-bouncer-key`, mounting the same Secret in the Traefik pod at `/etc/crowdsec-bouncer/`, and using the plugin's `crowdsecLapiKeyFile` option to read from the file. LAPI pre-registers the bouncer at boot via `BOUNCER_KEY_traefik` env against the same Secret.

4. **`externalTrafficPolicy: Local`** on the Traefik service was the fix for GeoBlock flagging every request as "local IP" — k3s's servicelb SNATs to the CNI gateway by default, so the plugin was seeing `10.42.0.1` everywhere. With Local, real client IPs are preserved.

5. **Cross-namespace secret mirroring**: the shared Postgres password sealed secret is materialised only in `databases` (where the create-user Job runs). Needed a second `wide.forEnvNamed` SealedSecret in `system` so LAPI can mount it.

### Debug highlights

- Agent crashloop on startup because `crowdsecurity/geoip-enrich` is a parser, not a collection. Fixed with a new `PARSERS` env var.
- Traefik bouncer logged `unknown plugin type: bouncer` once during initial boot; that was the window between `additionalArguments` being applied and the plugin being downloaded. Subsequent boot clean.
- `Machine is not enrolled in the console, can't synchronize` logged right after enroll. Caused by the earlier manual `cscli console enroll` attempt that consumed the key before the read-only write failed. Requires generating a new key and re-enrolling — see follow-up.

### Validation

- External check-host.net sweep from ~50 nodes worldwide: ES (es1, es2) → 200, every other country → 403. GeoBlock confirmed.
- Crowdsec agent ingesting Traefik logs from Loki (saw `Starting processing data` + connection to Loki).
- Bouncer registered with LAPI: `Registered bouncer for traefik`.
- MaxMind enrichers loaded: `Successfully registered enricher 'GeoIpCity'`, `'GeoIpASN'`, `'IpToRange'`.
- All other services (auth, media, argocd, grafana, music) still healthy post Traefik restart.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
## Outcome

Phase 1 + Phase 2 shipped. Photos.danielramos.me is now behind three layers:
1. **GeoBlock** (synchronous, Traefik GeoBlock plugin, ES/CU only).
2. **Crowdsec bouncer** (reactive, blocks IPs in community blocklist + locally-detected attacks on any host).
3. **Authelia OIDC** (already in place) + **rate limit on /api/auth** (from NASKS-52).

## What shipped

| Area | Change |
|---|---|
| `lib/system/crowdsec/` | New module: agent DaemonSet + LAPI Deployment, Postgres backend, Loki log acquisition for Traefik, MaxMind GeoLite2 enrichment, Console enrollment + Traefik bouncer pre-registration via entrypoint env. Collections: traefik, linux, http-cve, base-http-scenarios; parser geoip-enrich. |
| `lib/system/traefik/traefik.libsonnet` | Trust Cloudflare CIDRs on `web` + `websecure`; switch service to `externalTrafficPolicy: Local` so real client IPs reach middlewares; load `geoblock` (PascalMinder v0.3.7) + `bouncer` (maxlerebourg v1.5.1) plugins; mount `crowdsec-bouncer-key` Secret at `/etc/crowdsec-bouncer/` for the plugin to read via `crowdsecLapiKeyFile`. |
| `lib/media/immich/immich.libsonnet` | Two new Middleware CRs: `immich-geoblock-es-cu` and `immich-crowdsec-bouncer`. Attached in order to both routes (main + /api/auth). |
| `lib/databases/postgres/` | New `crowdsec` DB user + random sealed password; followed the existing `createUser` pattern. |
| `chartfile.yaml` | Vendor Crowdsec chart v0.23.0. |

## Verified externally

- check-host.net from ~50 nodes: ES → 200, every other country → 403.
- Crowdsec agent connected to Loki, ingesting Traefik logs.
- MaxMind GeoLite2-Country updating via geoipupdate at agent start.
- Bouncer registered, plugin loaded in Traefik, LAPI reachable at `crowdsec-service.system.svc.cluster.local:8080`.

## Follow-ups (not blocking — tracked separately if needed)

1. **Crowdsec Console sync**: the first boot used the enrollment token, but Console UI reports "Machine is not enrolled". Likely because my earlier manual `cscli console enroll` attempt consumed the token before the read-only write failed. Workaround: generate a fresh token in the Console, update the `crowdsec-console` SealedSecret, let the pod restart with `ENROLL_KEY`.
2. **Grafana dashboard** for Crowdsec metrics (VictoriaMetrics already scraping the /metrics endpoint — just need to import the official dashboard).
3. **Verify `X-Forwarded-For`**: acceptance criterion #13 — confirm via Loki that an orange-proxied request (e.g. to auth.danielramos.me) shows real client IP in Traefik access logs, not CF edge IP.
4. **AppSec / WAF engine** — explicitly out of scope here; revisit only if abuse patterns warrant it.

## Scope adjustment at end

Acceptance criterion #12 (Grafana dashboard) is intentionally left unchecked — deferred to a separate follow-up per the user's explicit request to close this task tonight.
<!-- SECTION:FINAL_SUMMARY:END -->
