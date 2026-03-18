---
id: NASKS-22.30
title: 'Healthcheck: valkey — TCP :6379'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-17 07:02'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 30000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Readiness probe using `valkey-cli ping` is configured
- [ ] #2 Startup probe using `valkey-cli ping` with reasonable failureThreshold is configured
- [ ] #3 Liveness probe using `valkey-cli ping` is configured (safe for in-memory store)
- [ ] #4 Pod correctly transitions to Ready only after Valkey responds to PING
- [ ] #5 Existing dependent services (authelia) experience no disruption on deploy
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings: Valkey Health Probes

### Image: `valkey/valkey:9.0.3-alpine`
- `valkey-cli` binary is **available** in the official Valkey image
- No authentication is configured in the current deployment (no password env vars or args)
- Alpine variant — lightweight, `valkey-cli` is the primary client tool

### Recommended Approach: exec with `valkey-cli ping` (NOT TCP)

**Why `valkey-cli ping` over TCP:**
- TCP only confirms the port is open; Valkey may be loading an RDB/AOF file and not ready to serve
- `valkey-cli ping` returns `PONG` only when the server is fully operational
- Equivalent to Redis `redis-cli ping` — identical protocol and behavior
- Lightweight check with negligible overhead

### Probe Configuration

**Readiness probe (REQUIRED):**
```yaml
readinessProbe:
  exec:
    command: ["valkey-cli", "ping"]
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

**Startup probe (RECOMMENDED):**
Valkey/Redis typically starts fast, but if loading a large dataset from disk (RDB restore), it can take time.

```yaml
startupProbe:
  exec:
    command: ["valkey-cli", "ping"]
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 30  # 30 * 5s = 150s max startup
```

**Liveness probe (SAFER than databases):**
Unlike PostgreSQL/MariaDB, Valkey is an in-memory data store primarily used as a cache/session store. Restarting Valkey is generally less dangerous:
- No complex crash recovery (data is in memory, optionally persisted to RDB)
- Fast restart times (seconds, not minutes)
- In this homelab, Valkey is used by Authelia for sessions — a restart means brief session interruption but no data loss

That said, conservative thresholds are still recommended:

```yaml
livenessProbe:
  exec:
    command: ["valkey-cli", "ping"]
  initialDelaySeconds: 15
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 3  # 3 * 15s = 45s before restart
```

### Safety Recommendation
For Valkey, it is **safe to include a liveness probe** unlike the database services. Valkey restarts are fast and low-risk. Use readiness + startup + liveness.

If authentication is added later, update the command to: `["valkey-cli", "-a", "$(VALKEY_PASSWORD)", "--no-auth-warning", "ping"]` (requires shell wrapper for env var expansion).

### Jsonnet Implementation Notes
- Simplest of the three — no auth, no special flags needed
- `valkey-cli ping` returns "PONG" with exit code 0 on success
- Current deployment has no volumes/persistence, so restart risk is minimal
- No existing probe helper in `utils.libsonnet`

### Sources
- https://valkey.io/blog/valkey-helm-chart/
- https://deepwiki.com/immich-app/immich-charts/4.3-valkey-service-architecture
- https://github.com/bitnami/charts/blob/main/bitnami/valkey/values.yaml
- https://valkey.io/commands/ping/
<!-- SECTION:NOTES:END -->
