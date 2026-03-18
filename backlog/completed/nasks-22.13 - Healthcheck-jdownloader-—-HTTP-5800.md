---
id: NASKS-22.13
title: 'Healthcheck: jdownloader — HTTP :5800/'
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
ordinal: 13000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `jlesage/jdownloader-2`
**Port:** 5800 (noVNC Web UI via nginx)
**Probe type:** HTTP GET

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 5800, path `/` — returns HTML noVNC interface (200 OK)
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 15
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- Port 5800 serves the noVNC HTML web interface via an internal nginx server
- No dedicated health endpoint; the root path `/` serves the web UI and returns 200 when ready
- Port 5900 is also available (raw VNC) but HTTP on 5800 is more suitable for probes
- The jlesage base image uses its own init system; allow adequate startup time
<!-- SECTION:NOTES:END -->
