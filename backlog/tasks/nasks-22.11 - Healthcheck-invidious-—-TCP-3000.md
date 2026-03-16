---
id: NASKS-22.11
title: 'Healthcheck: invidious — TCP :3000'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:26'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 11000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `quay.io/invidious/invidious`
**Port:** 3000
**Probe type:** HTTP GET (requires `statistics_enabled: true` in config)

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 3000, path `/api/v1/stats` — returns JSON with version/usage stats (200 OK)
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 30 (Crystal app + DB connection startup)
- **periodSeconds:** 30
- **timeoutSeconds:** 10
- **failureThreshold:** 3

### Notes
- The `/api/v1/stats` endpoint is the official health check path, used in Docker Compose healthcheck examples: `wget -nv --tries=1 --spider http://127.0.0.1:3000/api/v1/stats`
- **IMPORTANT:** Requires `statistics_enabled: true` in the Invidious config. Without this, the endpoint may not respond. Verify current config has this enabled.
- If `statistics_enabled` cannot be enabled, fall back to **TCP probe** on port 3000
- The root path `/` might redirect or require YouTube connectivity, making it unreliable for probes
- The stats endpoint returns JSON with software version, registration status, and usage metrics — lightweight and suitable for probing
<!-- SECTION:NOTES:END -->
