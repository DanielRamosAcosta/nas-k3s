---
title: 'Healthcheck: beets — HTTP :8337/'
status: Done
created_date: '2026-03-16 08:16'
labels:
  - infrastructure
  - reliability
dependencies: []
parent: "[[Añadir healthchecks (liveness readiness probes) a todos los servicios]]"
priority: 3
ordinal: 31000
---

## Implementation Notes

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
