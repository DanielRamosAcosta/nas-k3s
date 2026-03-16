---
id: NASKS-22.7
title: 'Healthcheck: gluetun — TCP :8888'
status: Done
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 7000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `ghcr.io/qdm12/gluetun:v3.41.1`
**Port:** 8888 (HTTP proxy), 9999 (health server, default localhost-only)
**Probe type:** HTTP GET on health server

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 9999, path `/` — returns 200 OK (healthy) or 500 (unhealthy)
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 30 (VPN connection establishment)
- **periodSeconds:** 30
- **timeoutSeconds:** 10 (health checks can be slow under load)
- **failureThreshold:** 3

### Required Environment Variable
- **`HEALTH_SERVER_ADDRESS=0.0.0.0:9999`** — CRITICAL: The default is `127.0.0.1:9999` (localhost only). For Kubernetes probes to reach the health server, it MUST be changed to bind to all interfaces (`0.0.0.0:9999`). Add this to the ConfigMap env vars.

### Notes
- Gluetun has a built-in health server that checks VPN connectivity via ICMP/DNS/TCP+TLS
- The health server runs its own internal check loop (default: every 5s). For Kubernetes, this loop coexists with the kubelet probe
- A PR (#2575) proposed a `/check` endpoint that performs on-demand health checks (bypassing the loop), but it was **NOT merged** as of research date
- The existing `/` endpoint on port 9999 returns the cached result from the internal health loop
- Under heavy VPN load, health checks may timeout — use generous `timeoutSeconds` (10s) and `failureThreshold` (3)
- `HEALTH_RESTART_VPN=off` can be set if you want Kubernetes to handle restarts instead of gluetun's internal auto-restart
- **Port 8888** (HTTP proxy) is NOT suitable for health checks — it forwards traffic through VPN, not a health indicator
- Need to add port 9999 to the container port list in the deployment spec
<!-- SECTION:NOTES:END -->
