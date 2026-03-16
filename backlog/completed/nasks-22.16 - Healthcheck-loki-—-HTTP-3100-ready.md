---
id: NASKS-22.16
title: 'Healthcheck: loki — HTTP :3100/ready'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://grafana.com/docs/loki/latest/reference/loki-http-api/'
  - 'https://github.com/grafana/helm-charts/issues/2968'
parent_task_id: NASKS-22
priority: low
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Loki does have an HTTP /ready endpoint. The earlier port-forward test was inconclusive but the endpoint is confirmed in official docs and Helm chart defaults. Upgrade from TCP probe to HTTP probe.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Endpoints (from official Grafana Loki HTTP API docs)
- **`/ready`** — Returns HTTP 200 when Loki is ready to accept traffic. Returns 503 during startup, shutdown, or when the ingester ring is not healthy. Use for **readiness probe**.
- **No separate liveness endpoint** — Loki does not expose a dedicated `/-/healthy` style endpoint. The official Helm chart uses `/ready` for **both** liveness and readiness probes (with different `initialDelaySeconds` and `failureThreshold`).

Both probes use the main HTTP port `:3100`.

### Recommended Probe Configuration
Following the pattern from the official Loki Helm chart:
```jsonnet
container.readinessProbe.httpGet.withPath('/ready') +
container.readinessProbe.httpGet.withPort(3100) +
container.readinessProbe.withInitialDelaySeconds(30) +
container.readinessProbe.withPeriodSeconds(10) +
container.readinessProbe.withTimeoutSeconds(1) +
container.readinessProbe.withFailureThreshold(3) +

container.livenessProbe.httpGet.withPath('/ready') +
container.livenessProbe.httpGet.withPort(3100) +
container.livenessProbe.withInitialDelaySeconds(45) +
container.livenessProbe.withPeriodSeconds(10) +
container.livenessProbe.withTimeoutSeconds(1) +
container.livenessProbe.withFailureThreshold(3)
```

### Key Considerations
- The earlier test via port-forward was inconclusive, but the `/ready` endpoint is well-documented and used by all official Helm chart deployments.
- In monolithic/single-binary mode (which this homelab uses), `/ready` checks that all components (ingester, querier, etc.) are initialized.
- After SIGTERM, Loki returns 503 on `/ready`, which is correct behavior for graceful shutdown.
- Using `/ready` for liveness is fine but use a higher `initialDelaySeconds` (45s) to avoid restart loops during slow startups. The Helm chart uses this same pattern.
- Port name in the existing StatefulSet is `loki` (3100) — can reference by name.

### Source
- https://grafana.com/docs/loki/latest/reference/loki-http-api/
- https://github.com/grafana/helm-charts/issues/2968
<!-- SECTION:NOTES:END -->
