---
id: NASKS-22.23
title: 'Healthcheck: prometheus — HTTP :9090 /-/healthy + /-/ready'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://prometheus.io/docs/prometheus/latest/management_api/'
parent_task_id: NASKS-22
priority: low
ordinal: 23000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Endpoints (from official Prometheus Management API docs)
- **`/-/healthy`** — Always returns HTTP 200 as long as the Prometheus process is running. Use for **liveness probe**.
- **`/-/ready`** — Returns HTTP 200 only when Prometheus is ready to serve traffic (respond to queries). Returns 503 during startup/shutdown. Use for **readiness probe**.

Both endpoints are on the main HTTP port `:9090`.

### Recommended Probe Configuration
```jsonnet
container.livenessProbe.httpGet.withPath('/-/healthy') +
container.livenessProbe.httpGet.withPort(9090) +
container.livenessProbe.withInitialDelaySeconds(30) +
container.livenessProbe.withPeriodSeconds(15) +
container.livenessProbe.withFailureThreshold(3) +

container.readinessProbe.httpGet.withPath('/-/ready') +
container.readinessProbe.httpGet.withPort(9090) +
container.readinessProbe.withInitialDelaySeconds(30) +
container.readinessProbe.withPeriodSeconds(5) +
container.readinessProbe.withFailureThreshold(3)
```

### Notes
- Port name in the existing StatefulSet is `prometheus` (9090) — can reference by name instead of number.
- No existing healthcheck/probe patterns in the codebase yet. This (or another service) will establish the pattern.
- Prometheus can take some time to load WAL on startup, so `initialDelaySeconds: 30` is reasonable.

### Source
- https://prometheus.io/docs/prometheus/latest/management_api/
<!-- SECTION:NOTES:END -->
