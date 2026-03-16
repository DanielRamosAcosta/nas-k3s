---
id: NASKS-22
title: Añadir healthchecks (liveness/readiness probes) a todos los servicios
status: Done
assignee: []
created_date: '2026-03-15 23:44'
updated_date: '2026-03-16 20:21'
labels:
  - infrastructure
  - reliability
dependencies: []
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Actualmente ningún servicio tiene liveness, readiness ni startup probes configurados. Kubernetes solo detecta si el proceso está corriendo, pero no si la aplicación responde correctamente.

Plan:
1. Crear helpers en `utils.libsonnet` para facilitar añadir probes de forma consistente (HTTP, TCP, exec).
2. Añadir probes a cada servicio según su tipo (HTTP endpoint, puerto TCP, etc.).
3. Validar con `tk eval` que los manifiestos generados son correctos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Helper en utils.libsonnet para añadir probes (HTTP, TCP)
- [ ] #2 authelia — TCP :9091
- [ ] #3 booklore — HTTP :6060/actuator/health
- [ ] #4 cloudflare-ddns — exec probe (no expone puerto HTTP)
- [ ] #5 deluge — HTTP :8112/
- [ ] #6 gitea — HTTP :3000/api/healthz
- [ ] #7 gluetun — TCP :8888
- [ ] #8 grafana — HTTP :3000/api/health
- [ ] #9 immich — HTTP :2283/api/server/ping
- [ ] #10 immich-machine-learning — TCP :3003
- [ ] #11 invidious — TCP :3000
- [ ] #12 invidious-companion — TCP :8282
- [ ] #13 jdownloader — HTTP :5800/
- [ ] #14 jellyfin — HTTP :8096/health
- [ ] #15 lidarr — HTTP :8686/ping
- [ ] #16 loki — TCP :3100 (no /ready confirmado)
- [ ] #17 mariadb — TCP :3306
- [ ] #18 navidrome — HTTP :4533/ping
- [ ] #19 node-exporter — TCP :9100
- [ ] #20 norznab — TCP :3000
- [ ] #21 nut-exporter — TCP :9199
- [ ] #22 postgres — TCP :5432
- [ ] #23 prometheus — HTTP :9090/-/ready (readiness) + /-/healthy (liveness)
- [ ] #24 promtail — HTTP :9080/ready
- [ ] #25 radarr — HTTP :7878/ping
- [ ] #26 sftpgo — HTTP :8080/healthz
- [ ] #27 slskd — HTTP :5030/health
- [ ] #28 smartctl-exporter — TCP :9633
- [ ] #29 sonarr — HTTP :8989/ping
- [ ] #30 valkey — TCP :6379
- [ ] #31 beets — HTTP :8337/
- [ ] #32 tk eval compila sin errores para todos los environments
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Para cada servicio, seguir este flujo:\n\n1. El usuario elige un servicio\n2. Investigar el healthcheck adecuado:\n   - Revisar documentación del servicio con context7\n   - Leer el README y otros markdowns del repo origen para ver si ya definen healthchecks o endpoints de salud\n   - Determinar tipo de probe (HTTP path, TCP port, exec command)\n3. Implementar el healthcheck solo para ese servicio\n4. Crear PR, esperar CI, squash merge\n5. Esperar a que ArgoCD despliegue (~20s)\n6. Verificar que el healthcheck funciona (pod Running, probes passing)\n7. Marcar el criterio de aceptación como hecho si todo va bien
<!-- SECTION:PLAN:END -->
