---
id: NASKS-22.31
title: 'Healthcheck: beets — HTTP :8337/'
status: Done
assignee: []
created_date: '2026-03-16 08:16'
updated_date: '2026-03-17 07:02'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 31000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `lscr.io/linuxserver/beets:2.6.1`
**Port:** 8337 (Web UI)
**Probe type:** HTTP GET

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 8337, path `/` — returns HTML web UI page (200 OK)
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 15 (LinuxServer s6-overlay init)
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- The web UI at `:8337/` serves an HTML page when beets is ready
- No dedicated health endpoint; the root path serves the web interface
- LinuxServer image uses s6-overlay, so allow startup time
- The beets web plugin must be enabled for the web UI to be accessible (verify this is configured)
<!-- SECTION:NOTES:END -->
