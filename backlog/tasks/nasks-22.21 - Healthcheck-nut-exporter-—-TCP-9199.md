---
id: NASKS-22.21
title: 'Healthcheck: nut-exporter — TCP :9199'
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
ordinal: 21000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `ghcr.io/druggeri/nut_exporter:3.2.5`
**Port:** 9199
**Probe type:** HTTP GET

### Recommended Configuration
- **Liveness probe:** `httpGet` on port 9199, path `/metrics` — returns exporter process metrics (200 OK)
- **Readiness probe:** same as liveness
- **initialDelaySeconds:** 10
- **periodSeconds:** 30
- **timeoutSeconds:** 5
- **failureThreshold:** 3

### Notes
- DRuggeri's nut_exporter exposes two metric paths:
  - `/ups_metrics` — UPS-specific metrics (requires `ups` query parameter when multiple UPS devices exist)
  - `/metrics` — exporter process metrics (always available, no parameters needed)
- The `/metrics` path is the best probe target: lightweight, always responds, no query params needed
- The root path `/` behavior is undocumented; `/metrics` is the safer choice
- The exporter needs to connect to a NUT server to serve UPS metrics, but `/metrics` (process metrics) works regardless of NUT connectivity, making it a good liveness indicator
- For a readiness probe that also validates NUT connectivity, `/ups_metrics?ups=<ups_name>` could be used, but this is more fragile
<!-- SECTION:NOTES:END -->
