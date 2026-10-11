---
title: 'Healthcheck: helper en utils.libsonnet'
status: Done
created_date: '2026-03-16 08:14'
labels:
  - infrastructure
  - reliability
dependencies: []
parent: "[[Añadir healthchecks (liveness readiness probes) a todos los servicios]]"
priority: 3
ordinal: 2000
---

## Description

Crear helpers para probes HTTP y TCP en lib/utils/probes.libsonnet y re-exportar desde utils.libsonnet

## Implementation Notes

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
