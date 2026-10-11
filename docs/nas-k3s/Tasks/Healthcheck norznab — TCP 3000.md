---
title: 'Healthcheck: norznab — TCP :3000'
status: Done
created_date: '2026-03-16 08:15'
labels:
  - infrastructure
  - reliability
dependencies: []
parent: "[[Añadir healthchecks (liveness readiness probes) a todos los servicios]]"
priority: 3
ordinal: 20000
---

## Implementation Notes

## Research Findings

**Image:** `ghcr.io/danielramosacosta/norznab` (custom image)
**Port:** 3000
**Probe type:** TCP (recommended)

### Recommended Configuration
- **Liveness probe:** `tcpSocket` on port 3000
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 10
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- This is a custom TypeScript app (Daniel's own project). No documented health endpoint was found.
- The app didn't respond to HTTP probes during testing, so TCP is the safest approach
- **Future improvement:** Consider adding a `/healthz` endpoint to the norznab source code for a proper HTTP probe. This would allow verifying the app is actually processing requests, not just accepting TCP connections.
- If an HTTP endpoint is added later, switch to `httpGet` probe for better health signal
