---
id: NASKS-22.5
title: 'Healthcheck: deluge — HTTP :8112/'
status: Done
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-17 07:02'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 5000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `linuxserver/deluge:2.2.0`
**Port:** 8112 (Web UI)
**Probe type:** HTTP GET

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 8112, path `/` — returns HTML web UI page (200 OK)
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 15 (LinuxServer images take a moment to initialize s6-overlay)
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- The web UI at `:8112/` returns an HTML page with 200 status when Deluge is ready
- No dedicated `/health` endpoint exists; the root path serves the login page
- Avoid using `curl` for exec probes on this image — a bug report (linuxserver/docker-deluge#193) showed high CPU usage with curl-based health checks. HTTP GET probe from kubelet avoids this issue entirely.
- LinuxServer images use s6-overlay init, so the `initialDelaySeconds` should be generous enough to allow startup
<!-- SECTION:NOTES:END -->
