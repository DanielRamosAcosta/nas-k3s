---
id: NASKS-22.6
title: 'Healthcheck: gitea — HTTP :3000/api/healthz'
status: Done
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://docs.gitea.com/installation/install-on-kubernetes'
parent_task_id: NASKS-22
priority: low
ordinal: 6000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Endpoint
- **Path:** `/api/healthz`
- **Port:** 3000 (same as main server, containerPort `server`)
- **Response:** HTTP 200 with JSON `{"status":"pass"}` plus component checks (cache, database connectivity with timestamps)
- **Auth:** No authentication required

### Recommended Probe Configuration (from Gitea Helm chart docs)
Gitea's official Kubernetes documentation recommends only a **liveness probe** (no separate readiness endpoint documented):

```yaml
livenessProbe:
  httpGet:
    path: /api/healthz
    port: 3000
  initialDelaySeconds: 200
  timeoutSeconds: 5
  periodSeconds: 10
  successThreshold: 1
  failureThreshold: 10
```

### Caveats
- The `initialDelaySeconds: 200` is high because Gitea may need time to run database migrations on first boot. For an established instance, this can likely be reduced (e.g., 30-60s), or better yet, use a **startupProbe** with a high failureThreshold to handle slow starts, and keep the liveness probe with a lower initialDelaySeconds.
- The `/api/healthz` endpoint checks both cache and database — it's a deep health check. This is fine for readiness but could cause unnecessary restarts if the database is temporarily slow. Consider using it for both liveness and readiness, but with a higher `failureThreshold` on the liveness probe.
- No separate readiness endpoint exists. Use the same `/api/healthz` for both.

### Implementation in Codebase
- File: `lib/media/gitea/gitea.libsonnet`
- Container port name: `server` (3000)
- Add httpGet probe targeting port `server`, path `/api/healthz`

### Sources
- https://docs.gitea.com/installation/install-on-kubernetes
<!-- SECTION:NOTES:END -->
