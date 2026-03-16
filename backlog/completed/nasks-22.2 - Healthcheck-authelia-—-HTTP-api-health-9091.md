---
id: NASKS-22.2
title: 'Healthcheck: authelia — HTTP /api/health :9091'
status: Done
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 2000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Authelia deployment has httpGet liveness probe on /api/health:9091
- [ ] #2 Authelia deployment has httpGet readiness probe on /api/health:9091
- [ ] #3 Probes use reasonable timeouts (initialDelay >= 5s, period 10-30s)
- [ ] #4 tk eval compiles without errors after adding probes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Health Endpoint

Authelia exposes an HTTP health endpoint at **`GET /api/health`** on port **9091** (the same port as the main application).

**Request**: `GET http://localhost:9091/api/health` (also supports HEAD)
**Response (200 OK)**:
```json
{"status": "OK"}
```

### Liveness vs Readiness

Currently (as of Authelia v4.x), **there is only one health endpoint** (`/api/health`). It functions as a **liveness check only** — it confirms the Authelia HTTP server can accept requests, but does NOT validate backend dependencies (LDAP, database, Redis).

There is an open feature request (authelia/authelia#10357) for a separate readiness endpoint that would validate upstream dependencies, but it has not been implemented yet. The Authelia team has acknowledged it as useful but low-priority.

**For our deployment**: Since we run a single replica with local dependencies, the liveness-only check at `/api/health` is sufficient for both liveness and readiness probes.

### Recommended Probe Configuration

```jsonnet
// Use httpGet instead of TCP — gives actual application-level health signal
livenessProbe: {
  httpGet: { path: '/api/health', port: 9091 },
  initialDelaySeconds: 10,
  periodSeconds: 30,
  timeoutSeconds: 5,
  failureThreshold: 3,
},
readinessProbe: {
  httpGet: { path: '/api/health', port: 9091 },
  initialDelaySeconds: 5,
  periodSeconds: 10,
  timeoutSeconds: 5,
  failureThreshold: 3,
},
```

### Caveats

1. **False positives**: `/api/health` returning 200 does NOT mean authentication is working — if LDAP/DB/Redis is down after startup, health will still report OK. For a single-replica homelab this is acceptable.
2. **No separate readiness endpoint**: Until Authelia implements a verbose health check, liveness and readiness probes will hit the same endpoint. This means K8s cannot distinguish "app crashed" from "app is up but dependencies are down."
3. **Port**: Health endpoint is on the same port (9091) as the main application — no separate metrics/health port.
4. **Authelia's own Docker healthcheck** uses the same endpoint via `healthcheck.sh` script bundled in the image, which runs: `wget --no-verbose --tries=1 --spider http://localhost:9091/api/health || exit 1`

### References
- Context7 Authelia docs: GET /api/health endpoint
- GitHub Issue #10357: verbose healthcheck feature request
- Authelia healthcheck.sh: https://github.com/authelia/authelia/blob/master/healthcheck.sh

### Current Codebase
- Authelia libsonnet: `lib/auth/authelia/authelia.libsonnet`
- Container port already named `http` on 9091
- Uses a Deployment (not StatefulSet), single replica
<!-- SECTION:NOTES:END -->
