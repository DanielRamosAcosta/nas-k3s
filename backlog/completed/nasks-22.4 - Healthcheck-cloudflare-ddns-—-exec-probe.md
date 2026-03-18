---
id: NASKS-22.4
title: 'Healthcheck: cloudflare-ddns — exec probe'
status: Done
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-17 07:02'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
No expone puerto HTTP. Necesita exec probe.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Research Findings

**Image:** `favonia/cloudflare-ddns:1.15.1`
**Ports:** None exposed
**Probe type:** None feasible (process liveness only)

### Recommended Configuration
- **No probe possible** — this is a scratch-based container with no shell, no HTTP server, and no exposed ports

### Why No Probe Works
1. **No HTTP port:** The container doesn't expose any HTTP endpoint
2. **No shell:** Built on `scratch` image — no `sh`, `bash`, `wget`, `curl`, or any binary exists for exec probes
3. **No health endpoint:** GitHub issue #706 requested a local health check endpoint, but the maintainer closed it, stating "I'm confident that this tool will never be unhealthy...any deviation will be considered a bug"
4. **exec probe impossible:** Kubernetes exec probes require a binary to execute inside the container; scratch images have none

### Alternatives Considered
- **HEALTHCHECKS_URL env var:** The app can ping external monitoring services (Healthchecks.io, Uptime Kuma) on successful DNS updates. This is an *outbound* notification, not a probe endpoint.
- **Process-based:** Kubernetes already restarts the pod if the main process (PID 1) exits. Since cloudflare-ddns runs as a long-lived process, a crash will trigger automatic restart via the deployment's `restartPolicy`.

### Recommendation
- **Skip health probes for this service.** The default Kubernetes behavior (restart on process exit) is sufficient.
- Optionally, configure `HEALTHCHECKS_URL` to ping an external monitor for observability, but this is outside the scope of K8s probes.
- Mark this task as done with "no probe needed" rationale.
<!-- SECTION:NOTES:END -->
