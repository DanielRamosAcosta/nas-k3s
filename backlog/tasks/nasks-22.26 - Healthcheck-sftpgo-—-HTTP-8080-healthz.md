---
id: NASKS-22.26
title: 'Healthcheck: sftpgo — HTTP :8080/healthz'
status: To Do
assignee: []
created_date: '2026-03-16 08:15'
updated_date: '2026-03-16 08:25'
labels:
  - infrastructure
  - reliability
dependencies: []
references:
  - 'https://docs.sftpgo.com/2.6/config-file/'
  - 'https://github.com/drakkan/sftpgo/discussions/665'
parent_task_id: NASKS-22
priority: low
ordinal: 26000
---

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

### Endpoint
- **Path:** `/healthz`
- **Port:** 8080 (httpd REST API port) — also available on telemetry port (9219 in our config)
- **Response:** HTTP 200 with plain text `ok`
- **Auth:** Authentication is always disabled for `/healthz`, even if auth is configured on the httpd server

### Port Considerations
The `/healthz` endpoint is available on **two** ports in the current deployment:
1. **Port 8080** (httpd) — the main REST API/web UI port. The OpenAPI spec includes `/healthz` as part of the httpd API with `security: []` (no auth).
2. **Port 9219** (telemetry) — already configured in `sftpgo.config.json`. The telemetry server also publishes `/healthz`.

**Recommendation:** Use port 8080 (`server`) for the health probe since it's the primary service port. If that port ever has proxy protocol issues, port 9219 (`metrics`) is a fallback.

### Recommended Probe Configuration
No separate liveness vs readiness endpoints exist. Use the same `/healthz` for both:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  timeoutSeconds: 3
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  timeoutSeconds: 3
  periodSeconds: 5
  failureThreshold: 3
```

### Caveats
- `/healthz` only checks that the process is running and responding — it does NOT verify database connectivity. For deeper checks, the `/api/v2/status` endpoint exists but requires authentication.
- If you need database-aware health checks, enable Prometheus metrics on the telemetry port (already done at 9219) and monitor `sftpgo_db_*` metrics externally.
- Issue #1961 documents a conflict with AWS NLB proxy protocol on the telemetry port — not relevant to this K3s deployment but worth noting.

### Implementation in Codebase
- File: `lib/media/sftpgo/sftpgo.libsonnet`
- Container port names: `server` (8080), `metrics` (9219)
- Add httpGet probe targeting port `server`, path `/healthz`

### Sources
- https://docs.sftpgo.com/2.6/config-file/ (telemetry section)
- https://github.com/drakkan/sftpgo/discussions/665 (health check discussion)
- SFTPGo OpenAPI spec (v2.3.0) — /healthz definition
<!-- SECTION:NOTES:END -->
