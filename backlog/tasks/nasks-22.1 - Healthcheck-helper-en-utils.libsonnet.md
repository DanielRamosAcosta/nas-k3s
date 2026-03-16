---
id: NASKS-22.1
title: 'Healthcheck: helper en utils.libsonnet'
status: In Progress
assignee: []
created_date: '2026-03-16 08:14'
updated_date: '2026-03-16 19:02'
labels:
  - infrastructure
  - reliability
dependencies: []
parent_task_id: NASKS-22
priority: low
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Crear helpers para probes HTTP y TCP en lib/utils/probes.libsonnet y re-exportar desde utils.libsonnet
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Defaults acordados para probes

### Stateless (mayoría de servicios)

**Readiness** (siempre):
```
initialDelaySeconds: 5
periodSeconds: 10
timeoutSeconds: 5
failureThreshold: 3      # 30s sin respuesta → quita tráfico
```

**Liveness** (siempre en stateless):
```
initialDelaySeconds: 15
periodSeconds: 30
timeoutSeconds: 5
failureThreshold: 3      # 90s sin respuesta → reinicia
```

**Startup** (solo apps lentas: booklore, jellyfin, immich-ml, gitea):
```
periodSeconds: 10
timeoutSeconds: 5
failureThreshold: 30     # hasta 5 minutos para arrancar
```

### Stateful (postgres, mariadb, valkey)
- Solo **readiness + startup**, sin liveness
- Restart automático es peligroso para bases de datos (corrupción, transacciones cortadas)
<!-- SECTION:NOTES:END -->
