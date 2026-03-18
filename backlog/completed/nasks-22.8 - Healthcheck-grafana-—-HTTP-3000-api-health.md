---
id: NASKS-22.8
title: 'Healthcheck: grafana — HTTP :3000/api/health'
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
ordinal: 8000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings: Grafana OSS Health Probes

### Health Endpoint

- **Path**: `GET /api/health`
- **Port**: `3000` (default Grafana HTTP port, matches the container port in `grafana.libsonnet`)
- **Auth**: No authentication required — suitable for probe use
- **Response (200 OK)**:
```json
{
  "commit": "087143285",
  "database": "ok",
  "version": "5.1.3"
}
```
The `database` field reports the status of the backend database connection (PostgreSQL in our case). This means the health endpoint implicitly checks DB connectivity.

### Liveness vs Readiness

Grafana does **not** have separate liveness and readiness endpoints. Both probes use `/api/health`. There is a known issue (grafana/helm-charts#2969) where `/api/health` returns 200 before the app is fully initialized during startup, which can cause premature traffic routing. The Grafana Helm chart maintainers have acknowledged this but as of now there is no separate `/ready` endpoint (unlike Loki, Mimir, Tempo which have `/ready`).

**Mitigation**: Use a `startupProbe` or a higher `initialDelaySeconds` on the readiness probe to avoid routing traffic before Grafana is fully ready.

### Recommended Probe Configuration

Based on the official Grafana Helm chart defaults (grafana/helm-charts) and Kubernetes best practices:

**Liveness Probe** (is the process alive?):
```jsonnet
livenessProbe: {
  httpGet: { path: '/api/health', port: 3000 },
  initialDelaySeconds: 60,
  timeoutSeconds: 30,
  periodSeconds: 10,
  failureThreshold: 10,
}
```

**Readiness Probe** (ready for traffic?):
```jsonnet
readinessProbe: {
  httpGet: { path: '/api/health', port: 3000 },
  initialDelaySeconds: 10,
  timeoutSeconds: 3,
  periodSeconds: 10,
  failureThreshold: 3,
  successThreshold: 1,
}
```

The Helm chart uses generous liveness defaults (`initialDelaySeconds: 60`, `failureThreshold: 10`) because Grafana can take time to start — especially when running DB migrations or provisioning dashboards/datasources.

### Implementation Notes for This Repo

- File to modify: `/Users/danielramos/Documents/repos/mines/nas-k3s/lib/monitoring/grafana/grafana.libsonnet`
- The deployment is created at line 15 using `deployment.new(...)`. Probes should be added to the container definition via `container.withLivenessProbe(...)` and `container.withReadinessProbe(...)` from k8s-libsonnet.
- Grafana connects to PostgreSQL (`postgres.databases.svc.cluster.local:5432`), so the `/api/health` endpoint's database check adds real value — if the DB connection is lost, the health check will reflect that.
- The container port `http` (3000) is already defined at line 17.

### Sources
- Grafana HTTP API docs: https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/other/
- Helm chart probe discussion: https://github.com/grafana/helm-charts/issues/2969
- Helm chart values.yaml: https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
- OpenAPI /api/health PR: https://github.com/grafana/grafana/pull/88203
<!-- SECTION:NOTES:END -->
