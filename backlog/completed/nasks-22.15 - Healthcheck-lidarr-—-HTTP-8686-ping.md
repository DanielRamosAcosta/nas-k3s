---
id: NASKS-22.15
title: 'Healthcheck: lidarr — HTTP :8686/ping'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-17 07:02'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 15000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 httpGet probe on /ping:8686 configured for both liveness and readiness
- [ ] #2 Probe is unauthenticated (no API key in probe config)
- [ ] #3 tk eval compiles without errors
- [ ] #4 Pod restarts correctly when Lidarr becomes unhealthy
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings (2026-03-16)

### Endpoint: `GET /ping` (confirmed from source code)

All three *arr apps (Sonarr, Radarr, Lidarr) share an **identical** PingController implementation. Verified directly from the source repositories:
- [Lidarr PingController.cs](https://github.com/Lidarr/Lidarr/blob/develop/src/Lidarr.Http/Ping/PingController.cs)

**Behavior:**
- Route: `GET /ping` and `HEAD /ping`
- Decorated with `[AllowAnonymous]` — **no API key or authentication required**
- Returns `{"status":"OK"}` with HTTP 200 on success
- Returns `{"status":"Error"}` with HTTP 500 on failure
- The endpoint queries the config DB (cached for 5s) — so it validates DB connectivity, not just that the process is alive
- Content-Type: `application/json`

### Probe Design

Since `/ping` checks DB connectivity, it serves as **both liveness and readiness**:
- If the DB is unreachable, the app returns 500 — it's not ready to serve requests
- If the process is hung and doesn't respond, the probe times out — it's not alive

**No separate liveness vs readiness endpoints exist.** Use `/ping` for both.

### Recommended Probe Configuration for Lidarr (port 8686)

```jsonnet
container.livenessProbe.httpGet.withPath('/ping')
+ container.livenessProbe.httpGet.withPort(8686)
+ container.livenessProbe.withInitialDelaySeconds(30)
+ container.livenessProbe.withPeriodSeconds(30)
+ container.livenessProbe.withTimeoutSeconds(5)
+ container.livenessProbe.withFailureThreshold(3)

container.readinessProbe.httpGet.withPath('/ping')
+ container.readinessProbe.httpGet.withPort(8686)
+ container.readinessProbe.withInitialDelaySeconds(15)
+ container.readinessProbe.withPeriodSeconds(15)
+ container.readinessProbe.withTimeoutSeconds(5)
+ container.readinessProbe.withFailureThreshold(3)
```

**Rationale for timeouts:**
- `initialDelaySeconds: 30` (liveness) / `15` (readiness): Lidarr takes ~10-20s to start on NAS hardware; gives headroom
- `periodSeconds: 30` (liveness) / `15` (readiness): Liveness can be less frequent; readiness should detect issues faster
- `timeoutSeconds: 5`: The /ping endpoint caches DB results for 5s, so 5s timeout is appropriate
- `failureThreshold: 3`: Standard — allows transient failures before restart/unready

### Implementation in Jsonnet

Edit `/Users/danielramos/Documents/repos/mines/nas-k3s/lib/arr/lidarr/lidarr.libsonnet`. No existing probe helpers in utils.libsonnet — use k8s-libsonnet container API directly. The container already has port named 'http' at 8686.

### Notes
- Hotio container images are just thin wrappers around the upstream binaries — they don't add their own health endpoints
- No startup probe needed: these apps start fast enough that initialDelaySeconds covers it
<!-- SECTION:NOTES:END -->
