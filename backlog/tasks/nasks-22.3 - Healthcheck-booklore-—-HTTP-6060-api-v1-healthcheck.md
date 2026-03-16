---
id: NASKS-22.3
title: 'Healthcheck: booklore — HTTP :6060/api/v1/healthcheck'
status: To Do
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-16 08:26'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://github.com/booklore-app/booklore/releases/tag/v1.16.2'
  - 'https://github.com/booklore-app/booklore/pull/2024'
parent_task_id: NASKS-22
priority: low
ordinal: 3000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings — Booklore Health Endpoint

### Endpoint (CORRECTED from original task title)
- **Path**: `/api/v1/healthcheck` (NOT `/actuator/health` as originally assumed)
- **Port**: 6060
- **Method**: GET
- **Added in**: v1.16.2 (PR #2024)
- **Auth**: Does not require authentication (explicitly designed for Docker/Podman/K8s monitoring)

The original task title referenced `/actuator/health` but Booklore uses a **custom healthcheck controller** at `/api/v1/healthcheck`. While Booklore is a Spring Boot app, it does NOT appear to expose standard Spring Boot Actuator health endpoints — the env config in the libsonnet even explicitly disables Swagger/SpringDoc (`SPRINGDOC_API_DOCS_ENABLED: 'false'`).

### Spring Boot Actuator liveness/readiness (likely NOT available)
Standard Spring Boot apps can expose `/actuator/health/liveness` and `/actuator/health/readiness`, but these are only auto-enabled when Spring Boot detects a Kubernetes environment OR when `management.endpoint.health.probes.enabled=true` is set. Booklore's Docker-oriented healthcheck suggests these are not configured. Use the single `/api/v1/healthcheck` endpoint for both liveness and readiness.

### Docker Compose reference values (from official Booklore docker-compose)
- **Interval**: 60s
- **Timeout**: 10s
- **Start period**: 60s (Spring Boot + MariaDB connection can be slow)
- **Retries**: 5
- **Command**: `wget -q -O - http://localhost:6060/api/v1/healthcheck`

### Recommended Kubernetes Probe Configuration
```jsonnet
// Liveness — restart if Booklore becomes unresponsive
livenessProbe: {
  httpGet: { path: '/api/v1/healthcheck', port: 6060 },
  initialDelaySeconds: 60,  // Spring Boot startup is slow
  periodSeconds: 30,
  timeoutSeconds: 10,
  failureThreshold: 3,
},
// Readiness — gate traffic until ready
readinessProbe: {
  httpGet: { path: '/api/v1/healthcheck', port: 6060 },
  initialDelaySeconds: 30,
  periodSeconds: 10,
  timeoutSeconds: 10,
  failureThreshold: 3,
},
// Startup — Spring Boot + DB init can be very slow
startupProbe: {
  httpGet: { path: '/api/v1/healthcheck', port: 6060 },
  periodSeconds: 10,
  failureThreshold: 30,  // 30 x 10s = 5 minutes max startup
  timeoutSeconds: 10,
},
```

### Why use a startupProbe
Booklore is a Spring Boot app that connects to MariaDB at startup. JVM warmup + Hibernate/JPA schema validation + connection pool init can easily take 30-90 seconds. A startupProbe with generous timeout prevents the liveness probe from killing the container during normal startup.

### Caveats
- The healthcheck endpoint was only added in v1.16.2. Ensure the deployed version is >= 1.16.2.
- Booklore depends on MariaDB (`mariadb.databases.svc.cluster.local:3306`). If the healthcheck validates DB connectivity, it may fail if MariaDB is down — this is appropriate for readiness but could cause restart loops for liveness. Monitor after deployment.
- Timeout of 10s (matching Docker compose) is recommended since Spring Boot health checks may need to verify DB connections.

### Source files
- Lib: `lib/media/booklore/booklore.libsonnet`
- Container port name: `server` (6060)
- No existing probes configured

### References
- https://github.com/booklore-app/booklore/releases/tag/v1.16.2
- https://github.com/booklore-app/booklore/pull/2024
<!-- SECTION:NOTES:END -->
