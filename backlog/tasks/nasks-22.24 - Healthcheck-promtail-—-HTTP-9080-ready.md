---
id: NASKS-22.24
title: 'Healthcheck: promtail — HTTP :9080/ready'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:23'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://grafana.com/docs/loki/latest/send-data/promtail/configuration/'
  - 'https://github.com/grafana/loki/pull/468'
parent_task_id: NASKS-22
priority: low
ordinal: 24000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Endpoints (from official Grafana Promtail docs)
- **`/ready`** — Returns HTTP 200 when Promtail is up and running AND there is at least one working target. Use for **readiness probe**.
- **No separate liveness endpoint** — Promtail does not expose a dedicated liveness endpoint. The `/ready` endpoint was specifically added (grafana/loki PR #468) as a readiness probe patterned after Loki's `/ready`.

The Promtail HTTP server runs on port `:9080` by default (configurable via `server.http_listen_port`).

### Important: Container Port Not Currently Exposed
The existing `promtail.libsonnet` does NOT define any `containerPort` entries on the DaemonSet container. To use HTTP probes, the port 9080 needs to be either:
1. Added as a named containerPort (recommended for clarity), OR
2. Referenced directly by number in the probe (works without declaring the port)

### Recommended Probe Configuration
```jsonnet
// First, add containerPort to the container definition:
container.withPorts([containerPort.new('http', 9080)]) +

// Then add probes:
container.readinessProbe.httpGet.withPath('/ready') +
container.readinessProbe.httpGet.withPort(9080) +
container.readinessProbe.withInitialDelaySeconds(10) +
container.readinessProbe.withPeriodSeconds(10) +
container.readinessProbe.withFailureThreshold(5) +

container.livenessProbe.httpGet.withPath('/ready') +
container.livenessProbe.httpGet.withPort(9080) +
container.livenessProbe.withInitialDelaySeconds(10) +
container.livenessProbe.withPeriodSeconds(10) +
container.livenessProbe.withFailureThreshold(5)
```

### Key Considerations
- `/ready` returns 200 only when at least one target is active. For liveness, this is slightly aggressive — if Promtail temporarily loses all targets, it would report not-ready AND trigger a restart. Use a generous `failureThreshold` (5) to avoid unnecessary restarts.
- The `health_check_target` config option (default: `true`) controls whether Promtail checks target health for the `/ready` response. If set to `false`, `/ready` always returns 200 when the process is running. Consider setting this to `false` if the liveness probe causes restart loops due to transient target loss.
- Promtail starts quickly (no WAL, no heavy init), so `initialDelaySeconds: 10` is sufficient.
- Alternative: use `/ready` only for readiness, and a simple TCP probe on 9080 for liveness (avoids the target-dependent behavior for restarts).

### Source
- https://grafana.com/docs/loki/latest/send-data/promtail/configuration/
- https://github.com/grafana/loki/pull/468
<!-- SECTION:NOTES:END -->
