---
id: NASKS-22.12
title: 'Healthcheck: invidious-companion — TCP :8282'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 12000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `quay.io/invidious/invidious-companion`
**Port:** 8282
**Probe type:** TCP (recommended) or HTTP GET

### Recommended Configuration
- **Liveness probe:** `tcpSocket` on port 8282
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 20 (companion needs to fetch potoken on startup, which can take time)
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- The companion serves endpoints under `/companion` path prefix (e.g., `http://companion:8282/companion`)
- No documented `/healthz` or dedicated health check endpoint exists in the invidious-companion project
- HTTP GET on `/companion` may work but is not officially documented as a health endpoint
- TCP probe is the safest choice given lack of documented health endpoints
- **Startup consideration:** On blocked IPs, the companion tries to fetch a potoken 5 times on startup before the webserver boots. This means the TCP probe will fail during that period — use generous `initialDelaySeconds` or a separate `startupProbe`
- Consider a `startupProbe` with `failureThreshold: 10` and `periodSeconds: 10` to handle slow potoken fetching
<!-- SECTION:NOTES:END -->
