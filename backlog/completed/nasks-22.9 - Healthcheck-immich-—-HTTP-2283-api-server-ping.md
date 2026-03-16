---
id: NASKS-22.9
title: 'Healthcheck: immich — HTTP :2283/api/server/ping'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 19:05'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - >-
    https://github.com/immich-app/immich-charts/blob/main/charts/immich/templates/server.yaml
  - 'https://github.com/immich-app/immich/pull/9583'
  - 'https://github.com/immich-app/immich/discussions/6320'
parent_task_id: NASKS-22
priority: low
ordinal: 3000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings (2026-03-16)

### Health Endpoint
- **Path:** `GET /api/server/ping` on port **2283**
- **Response:** `{"res": "pong"}` with HTTP 200
- **Auth required:** No (public endpoint)
- Confirmed working in our cluster and documented in Immich OpenAPI spec.

### Official Helm Chart Probe Configuration (immich-app/immich-charts)
Source: `charts/immich/templates/server.yaml`

**Startup Probe:**
- httpGet path: `/api/server/ping`, port: `http` (2283)
- initialDelaySeconds: 0
- periodSeconds: 10
- timeoutSeconds: 1
- failureThreshold: **30** (allows up to 300s for startup — DB migrations, etc.)

**Liveness Probe:**
- httpGet path: `/api/server/ping`, port: `http` (2283)
- initialDelaySeconds: 0
- periodSeconds: 10
- timeoutSeconds: 1
- failureThreshold: 3

**Readiness Probe:**
- Identical to liveness probe (same path, port, and thresholds)

### Notes for Implementation
- All three probes (startup, liveness, readiness) use the same HTTP endpoint.
- The startup probe has a high failureThreshold (30) to accommodate DB migrations on version upgrades.
- The Immich Docker image also includes a built-in healthcheck script at `/usr/src/app/bin/immich-healthcheck` (Node.js-based, added in PR #9583), but for Kubernetes we should use native httpGet probes instead.
- Our statefulset container port is already named `server` on 2283 — use that port name in the probe spec.
- The container in our libsonnet is at `/Users/danielramos/Documents/repos/mines/nas-k3s/lib/media/immich/immich.libsonnet` lines 18-46.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `withStartup` probes (readiness + liveness + startup) to the immich server container using `u.probes.withStartup.http('/api/server/ping', 2283)`.

**File changed:** `lib/media/immich/immich.libsonnet` — added probe mixin to the main container.

All three probes use the `/api/server/ping` endpoint (public, no auth). The startup probe allows up to ~5min for DB migrations.
<!-- SECTION:FINAL_SUMMARY:END -->
