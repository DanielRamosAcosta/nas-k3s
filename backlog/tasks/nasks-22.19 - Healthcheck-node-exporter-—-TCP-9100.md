---
id: NASKS-22.19
title: 'Healthcheck: node-exporter — TCP :9100'
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
ordinal: 19000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `quay.io/prometheus/node-exporter:v1.10.2`
**Port:** 9100
**Probe type:** HTTP GET

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 9100, path `/` — returns a landing/index page (200 OK) with link to `/metrics`
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 10
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- Node exporter does NOT have dedicated `/-/healthy` or `/-/ready` endpoints (unlike Prometheus server itself)
- The `/metrics` endpoint works for health checking but returns a large response body with all system metrics — wasteful for a probe
- The root path `/` returns a lightweight HTML landing page, making it the best probe target
- Node exporter starts quickly as it's a single Go binary
- This runs as a DaemonSet, so probes are especially important to detect per-node failures
<!-- SECTION:NOTES:END -->
