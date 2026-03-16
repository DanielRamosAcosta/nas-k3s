---
id: NASKS-22.27
title: 'Healthcheck: slskd — HTTP :5030/health'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://github.com/slskd/slskd/issues/17'
  - 'https://github.com/slskd/slskd/issues/99'
  - 'https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks'
parent_task_id: NASKS-22
priority: low
ordinal: 27000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings — slskd Health Endpoint

### Endpoint
- **Path**: `/health`
- **Port**: 5030
- **Method**: GET
- **Response (healthy)**: HTTP 200, plaintext body `Healthy`
- **Response (degraded)**: HTTP 200, plaintext body `Degraded`
- **Response (unhealthy)**: HTTP 503, plaintext body `Unhealthy`
- **Framework**: ASP.NET Core built-in health checks (Microsoft.Extensions.Diagnostics.HealthChecks)

slskd is built on ASP.NET Core which provides a standard health check framework. The Dockerfile includes a `HEALTHCHECK` instruction using `wget` against `/health`. The endpoint was added as part of issue #17.

### What it checks
Per the original issue, the initial implementation is a **basic/static health check** — it confirms the HTTP server is responding. It does NOT currently verify:
- Soulseek network connection status
- Distributed network parent connection
- Incoming connections / port forwarding
- I/O health of shared/download directories

These were listed as future enhancements in the original issue but the endpoint was shipped with just the basic check.

### Caveats
- **Startup time**: slskd's health check startup was extended to 60 minutes in a past release (issue #99), suggesting the Soulseek connection can take a long time to establish. However, the `/health` endpoint itself (HTTP server check) should respond quickly even before the Soulseek connection is established.
- Since the health check is basic (HTTP server only), it won't detect issues with the Soulseek network — the service could show "Healthy" while unable to search or download. This is acceptable for liveness (restart only if truly crashed) but means readiness won't gate on Soulseek connectivity.

### Recommended Kubernetes Probe Configuration
```jsonnet
// Liveness — restart if slskd HTTP server is unresponsive
livenessProbe: {
  httpGet: { path: '/health', port: 5030 },
  initialDelaySeconds: 15,
  periodSeconds: 30,
  timeoutSeconds: 5,
  failureThreshold: 3,
},
// Readiness — same endpoint, tighter timing
readinessProbe: {
  httpGet: { path: '/health', port: 5030 },
  initialDelaySeconds: 10,
  periodSeconds: 10,
  timeoutSeconds: 5,
  failureThreshold: 3,
},
// Startup — slskd starts relatively fast but give some room
startupProbe: {
  httpGet: { path: '/health', port: 5030 },
  periodSeconds: 5,
  failureThreshold: 24,  // 24 x 5s = 2 minutes max startup
  timeoutSeconds: 5,
},
```

### Source files
- Lib: `lib/arr/slskd/slskd.libsonnet`
- Container port name: `http` (5030)
- No existing probes configured

### References
- https://github.com/slskd/slskd/issues/17
- https://github.com/slskd/slskd/issues/99
- https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks
<!-- SECTION:NOTES:END -->
