---
id: NASKS-22.18
title: 'Healthcheck: navidrome — HTTP :4533/ping'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:25'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://github.com/navidrome/navidrome/issues/773'
parent_task_id: NASKS-22
priority: low
ordinal: 18000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Endpoint
- **Path:** `/ping`
- **Port:** 4533 (same as main server, containerPort `server`)
- **Response:** HTTP 200 with plain text `.` (a single dot)
- **Auth:** No authentication required (unauthenticated endpoint)

### Evidence
- The official Navidrome Docker image includes a built-in HEALTHCHECK: `wget -O- http://localhost:${ND_PORT}/ping || exit 1`
- This is a lightweight, purpose-built health endpoint — NOT the Subsonic API `/rest/ping.view` (which requires authentication parameters `u`, `v`, `c`)
- The `/ping` endpoint is registered directly on the HTTP router, separate from the Subsonic API routes

### Recommended Probe Configuration
No separate liveness vs readiness endpoints exist. Use `/ping` for both:

```yaml
livenessProbe:
  httpGet:
    path: /ping
    port: 4533
  initialDelaySeconds: 10
  timeoutSeconds: 3
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ping
    port: 4533
  initialDelaySeconds: 5
  timeoutSeconds: 3
  periodSeconds: 5
  failureThreshold: 3
```

### Caveats
- `/ping` is a shallow health check — it confirms the HTTP server is responsive but does not verify database connectivity or music library scanning status.
- Navidrome also has a `/rest/ping.view` Subsonic API endpoint, but that requires authentication parameters and is NOT suitable for Kubernetes probes.
- The Docker HEALTHCHECK uses `wget` because the Navidrome image is based on Alpine and does not include `curl`. This is irrelevant for Kubernetes httpGet probes (kubelet handles the HTTP request natively).
- Low `initialDelaySeconds` is fine — Navidrome starts quickly (no heavy migrations on established instances).

### Implementation in Codebase
- File: `lib/media/navidrome/navidrome.libsonnet`
- Container port name: `server` (4533)
- Add httpGet probe targeting port `server`, path `/ping`

### Sources
- Navidrome Docker image Dockerfile (HEALTHCHECK directive)
- https://github.com/navidrome/navidrome/issues/773
<!-- SECTION:NOTES:END -->
