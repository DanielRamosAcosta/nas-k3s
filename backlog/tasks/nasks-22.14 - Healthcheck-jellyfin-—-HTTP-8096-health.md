---
id: NASKS-22.14
title: 'Healthcheck: jellyfin — HTTP :8096/health'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:26'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - >-
    https://jellyfin.org/docs/general/post-install/networking/advanced/monitoring/
  - 'https://github.com/jellyfin/jellyfin/issues/9954'
parent_task_id: NASKS-22
priority: low
ordinal: 14000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings — Jellyfin Health Endpoint

### Endpoint
- **Path**: `/health`
- **Port**: 8096
- **Method**: GET
- **Response (healthy)**: HTTP 200, plaintext body `Healthy`
- **Response (unhealthy)**: Non-200 status code
- **What it checks**: HTTP and database connectivity (per official docs)

### Caveats
- **CRITICAL — Startup migrations**: The health endpoint does NOT function correctly while the server is still starting up or running database migrations. A liveness probe that fires too early will kill the container during migrations. This was explicitly called out in the Jellyfin monitoring docs.
- **Known issue (jellyfin/jellyfin#9954)**: There have been reports of the `/health` endpoint returning "healthy" even when the server has a broken SQLite database (disk I/O errors). The health check may be more superficial than expected — it does not fully validate database integrity.

### Recommended Kubernetes Probe Configuration
```jsonnet
// Liveness — restart if Jellyfin becomes unresponsive
livenessProbe: {
  httpGet: { path: '/health', port: 8096 },
  initialDelaySeconds: 120,  // generous: Jellyfin migrations can be slow
  periodSeconds: 30,
  timeoutSeconds: 5,
  failureThreshold: 3,
},
// Readiness — same endpoint, tighter timing
readinessProbe: {
  httpGet: { path: '/health', port: 8096 },
  initialDelaySeconds: 30,
  periodSeconds: 10,
  timeoutSeconds: 5,
  failureThreshold: 3,
},
// Startup — protect against slow first boot / migration
startupProbe: {
  httpGet: { path: '/health', port: 8096 },
  periodSeconds: 10,
  failureThreshold: 30,  // 30 x 10s = 5 minutes max startup
  timeoutSeconds: 5,
},
```

### Why use a startupProbe
A startupProbe is essential here because Jellyfin can take several minutes on first boot or after upgrades when running database migrations. Without it, the liveness probe would kill the container before it finishes starting. Once the startupProbe succeeds, liveness and readiness take over.

### Source files
- Lib: `lib/media/jellyfin/jellyfin.libsonnet`
- Container port name: `http` (8096)
- No existing probes configured

### References
- https://jellyfin.org/docs/general/post-install/networking/advanced/monitoring/
- https://github.com/jellyfin/jellyfin/issues/9954
<!-- SECTION:NOTES:END -->
