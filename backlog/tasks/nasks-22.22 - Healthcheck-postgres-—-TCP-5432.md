---
id: NASKS-22.22
title: 'Healthcheck: postgres — TCP :5432'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:23'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 22000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Readiness probe using `pg_isready -U postgres` is configured
- [ ] #2 Startup probe using `pg_isready` with failureThreshold >= 30 is configured
- [ ] #3 Liveness probe is either omitted (preferred) or uses very conservative thresholds (failureThreshold >= 5, periodSeconds >= 30)
- [ ] #4 Pod correctly transitions to Ready only after PostgreSQL accepts connections
- [ ] #5 Existing dependent services (immich, authelia, gitea, etc.) are unaffected
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings: PostgreSQL Health Probes

### Image: `ghcr.io/immich-app/postgres` (based on official PostgreSQL)
- `pg_isready` binary is **available** in the image (confirmed by Immich docs using it for healthchecks)

### Recommended Approach: exec with `pg_isready` (NOT TCP)

**Why `pg_isready` over TCP:**
- TCP only confirms the port is open, not that PostgreSQL is actually accepting connections
- `pg_isready` checks the actual PostgreSQL wire protocol and returns meaningful status
- `pg_isready` exit codes: 0 = accepting connections, 1 = rejecting connections, 2 = no response
- Minimal overhead — it's a lightweight client-side check, no SQL query executed

### Probe Configuration

**Readiness probe (REQUIRED):**
```yaml
readinessProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Startup probe (REQUIRED):**
```yaml
startupProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 30  # 30 * 5s = 150s max startup time
```

**Liveness probe (CAREFUL — use conservative settings):**
Databases are stateful — an aggressive liveness probe that triggers a restart can cause data corruption or long recovery times. If used at all, it must have very generous thresholds.

```yaml
livenessProbe:
  exec:
    command: ["pg_isready", "-U", "postgres"]
  initialDelaySeconds: 30
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 5  # 5 * 30s = 150s before restart
```

**Alternative: Skip liveness probe entirely.** Many production PostgreSQL deployments intentionally omit liveness probes because:
1. A restart during a long-running query or vacuum can cause corruption
2. If postgres is truly stuck, the readiness probe removes it from service endpoints
3. Manual intervention is safer than automated restarts for databases

### Safety Recommendation
Start with **readiness + startup only** (no liveness). Add liveness later only if there's evidence of PostgreSQL getting into unrecoverable deadlocked states that require a restart.

### Jsonnet Implementation Notes
- The username "postgres" should match the `POSTGRES_USER` env var from the sealed secret. Since we can't easily reference env vars in probe commands, hardcoding "postgres" works because that's the standard superuser.
- Use `container.mixin.readinessProbe.exec.withCommand(...)` or raw object mixin in Jsonnet.
- No existing probe helper in `utils.libsonnet` — either add one or use raw k8s API bindings.

### Sources
- https://nieldw.medium.com/kubernetes-probes-for-postgresql-pods-a66d707df6b4
- https://srcco.de/posts/kubernetes-liveness-probes-are-dangerous.html
- https://blog.colinbreck.com/kubernetes-liveness-and-readiness-probes-how-to-avoid-shooting-yourself-in-the-foot/
<!-- SECTION:NOTES:END -->
