---
id: NASKS-22.17
title: 'Healthcheck: mariadb — TCP :3306'
status: Done
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 17000
---

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Readiness probe using `mysqladmin ping -h localhost` is configured
- [ ] #2 Startup probe using `mysqladmin ping` with failureThreshold >= 60 is configured (critical to avoid init restart loop)
- [ ] #3 Liveness probe is either omitted (preferred) or uses very conservative thresholds (failureThreshold >= 5, periodSeconds >= 30)
- [ ] #4 Verify `mysqladmin` binary exists in the linuxserver/mariadb image before deploying (run `kubectl exec` test)
- [ ] #5 Pod correctly transitions to Ready only after MariaDB accepts connections
- [ ] #6 Existing dependent services (booklore) are unaffected
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings: MariaDB Health Probes

### Image: `lscr.io/linuxserver/mariadb:11.4.8-r0-ls201` (LinuxServer)
- `mysqladmin` binary is **available** in the linuxserver/mariadb image (documented in their docs for post-setup admin tasks)
- The official MariaDB `healthcheck.sh` script is **NOT available** — that's only in the Docker Official `mariadb` image, not LinuxServer's
- MariaDB 11.x removed `mysqladmin` from the official image, but LinuxServer's build still includes it

### Recommended Approach: exec with `mysqladmin ping` (NOT TCP)

**Why `mysqladmin ping` over TCP:**
- TCP only confirms the port is open; MariaDB may be in crash recovery or initializing
- `mysqladmin ping` verifies the MySQL protocol is responsive and the server is accepting commands
- Returns exit code 0 when the server responds to ping, non-zero otherwise

### Probe Configuration

**Key concern — LinuxServer image specifics:**
- LinuxServer images run as root internally and use s6-overlay for init
- The MariaDB root user uses unix socket auth by default, so `mysqladmin ping` without `-u`/`-p` should work when executed inside the container as root
- If password auth is required, the env vars `MYSQL_ROOT_PASSWORD` can be referenced

**Readiness probe (REQUIRED):**
```yaml
readinessProbe:
  exec:
    command: ["mysqladmin", "ping", "-h", "localhost"]
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Startup probe (REQUIRED — critical for MariaDB):**
MariaDB's first-run initialization (creating system tables, running init scripts) can take significant time. Without a startup probe, a liveness probe can restart the container during init, causing an infinite restart loop because the init script only runs if the data directory is empty.

```yaml
startupProbe:
  exec:
    command: ["mysqladmin", "ping", "-h", "localhost"]
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 60  # 60 * 10s = 600s (10 min) max startup
```

**Liveness probe (CAREFUL — same database concerns as PostgreSQL):**
```yaml
livenessProbe:
  exec:
    command: ["mysqladmin", "ping", "-h", "localhost"]
  initialDelaySeconds: 30
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 5  # 5 * 30s = 150s before restart
```

### Safety Recommendation
Start with **readiness + startup only** (no liveness). The startup probe is especially critical for MariaDB because of the documented issue where liveness probes during initialization cause infinite restart loops. Add liveness later only if needed.

### Jsonnet Implementation Notes
- The `-h localhost` flag ensures we connect via TCP to localhost rather than the unix socket, which is more reliable for health checks
- If `mysqladmin` requires authentication, use: `["mysqladmin", "ping", "-h", "localhost", "--user=root", "--password=$MYSQL_ROOT_PASSWORD"]` via a shell wrapper, but test socket auth first
- No existing probe helper in `utils.libsonnet`

### Sources
- https://mariadb.org/mariadb-server-docker-official-images-healthcheck-without-mysqladmin/
- https://discourse.linuxserver.io/t/running-health-checks-with-lscr-io-linuxserver-mariadb-latest/10464
- https://sideshowcoder.com/2023/01/10/mariadb-kubernetes-setup/
- https://srcco.de/posts/kubernetes-liveness-probes-are-dangerous.html
<!-- SECTION:NOTES:END -->
