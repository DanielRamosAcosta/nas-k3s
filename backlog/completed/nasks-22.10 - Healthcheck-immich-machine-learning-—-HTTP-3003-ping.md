---
id: NASKS-22.10
title: 'Healthcheck: immich-machine-learning — HTTP :3003/ping'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - >-
    https://github.com/immich-app/immich-charts/blob/main/charts/immich/templates/machine-learning.yaml
  - 'https://github.com/immich-app/immich/pull/9583'
  - >-
    https://deepwiki.com/immich-app/immich-charts/3.3-machine-learning-configuration
parent_task_id: NASKS-22
priority: low
ordinal: 10000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings (2026-03-16)

### Health Endpoint
- **Path:** `GET /ping` on port **3003** (NOT `/api/server/ping` — ML has its own simpler endpoint)
- **Response:** HTTP 200 when healthy
- **Auth required:** No
- **Important:** The task was originally filed as TCP-only, but the ML service actually exposes an HTTP `/ping` endpoint, so we should use httpGet probes (not tcpSocket).

### Official Helm Chart Probe Configuration (immich-app/immich-charts)
Source: `charts/immich/templates/machine-learning.yaml`

**Startup Probe:**
- httpGet path: `/ping`, port: `http` (3003)
- initialDelaySeconds: 0
- periodSeconds: 10
- timeoutSeconds: 1
- failureThreshold: **60** (allows up to 600s / 10 minutes for startup)

**Liveness Probe:**
- httpGet path: `/ping`, port: `http` (3003)
- periodSeconds: 10
- timeoutSeconds: 1
- failureThreshold: 3

**Readiness Probe:**
- Identical to liveness probe (same path, port, and thresholds)

### Notes for Implementation
- The startup probe has a very generous failureThreshold (60 = 10 minutes) because on first start or after cache eviction, the ML service downloads AI models (CLIP, facial recognition) which can take several minutes.
- Our ML deployment already has the container port named `http` on 3003 — use that port name in the probe spec.
- The ML service uses a Python-based healthcheck (added in PR #9583) internally, but for K8s we use native httpGet probes.
- The container in our libsonnet is at `/Users/danielramos/Documents/repos/mines/nas-k3s/lib/media/immich/immich.libsonnet` lines 72-101 (mlDeployment).
- Consider the resource-intensive startup: the ML container requests 2Gi memory / 1 CPU and limits at 6Gi / 4 CPU. Model loading is CPU and memory intensive, which is why the startup probe needs a long window.
<!-- SECTION:NOTES:END -->
