---
id: NASKS-22.28
title: 'Healthcheck: smartctl-exporter — TCP :9633'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:27'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 28000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `quay.io/prometheuscommunity/smartctl-exporter:v0.14.0`
**Port:** 9633
**Probe type:** HTTP GET

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 9633, path `/` — returns a landing page (200 OK) with link to `/metrics`
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 15 (needs to discover and scan SMART devices on startup)
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- smartctl_exporter (prometheus-community) generates a landing page at `/` when the metrics path is not set to root — this is a lightweight HTML page suitable for probing
- The `/metrics` endpoint returns SMART data from all discovered devices. It works as a health check but the response is heavier than the landing page.
- The exporter runs with `--privileged` or appropriate capabilities to access disk devices
- It periodically polls devices for SMART data and caches it, so the `/metrics` response is from cache (fast)
- Single Go binary, starts quickly
<!-- SECTION:NOTES:END -->
