---
title: Separar Immich y ArgoCD en DBs lógicas distintas de Valkey (colisión en /0)
status: In Progress
created_date: '2026-05-08 06:01'
labels:
  - databases
  - tech-debt
dependencies: []
priority: 3
ordinal: 63000
---

## Description

## Problema

Tanto **Immich** (`lib/media/immich/immich.libsonnet`) como **ArgoCD** (`lib/system/argocd/argocd.libsonnet`) apuntan a `valkey.databases.svc.cluster.local` sin especificar DB index → ambos usan el `/0` por defecto.

No ha causado incidencias visibles (los keys no colisionan por nombre), pero rompe el aislamiento lógico de Redis y dificulta operaciones como `FLUSHDB` por servicio.

## Convención propuesta

Asignar índices secuenciales reservados por servicio:

| Servicio | DB índice |
|----------|-----------|
| Immich   | `/0`      |
| ArgoCD   | `/1`      |
| wger cache    | `/2` |
| wger celery broker | `/3` |
| wger celery backend | `/4` |

A partir de ahí, cada nuevo servicio toma el siguiente índice libre y se documenta aquí.

## Acciones

- Configurar Immich con `REDIS_DBINDEX=0` explícito (o equivalente) — ya está implícito, pero hacerlo explícito.
- Configurar ArgoCD Helm chart para apuntar a `/1`.
- Documentar la tabla de asignación en `lib/databases/valkey/README.md` (crear si no existe) o en el header del libsonnet.

## Fuera de alcance

- Migrar datos: ambos servicios pueden perder cache (regenerable). No hay datos persistentes en Valkey.

## Implementation Plan

Valkey corre con config por defecto y **sin volumen persistente** → ya es 100% volátil (pierde todo en cada reinicio del pod) y expone las 16 DBs por defecto. wger ya sigue la convención (`/2` cache, `/3` celery broker, `/4` celery backend). Solo faltan Immich y ArgoCD.

- **Immich** (`lib/media/immich/immich.libsonnet`): añadir `REDIS_DBINDEX: '0'` explícito al `configEnv` (ya era `/0` implícito; se hace explícito por claridad).
- **ArgoCD** (`lib/system/argocd/argocd.libsonnet`): añadir `'redis.db': 1` a `configs.params`. El chart lo propaga a `argocd-cmd-params-cm` → env `REDISDB` en server/repo-server/application-controller.
- Migración "a lo bestia" sin mover datos: al desplegar, ArgoCD reconecta a `/1` (vacía) y reconstruye su caché de manifiestos/diffs en segundos. Las keys viejas en `/0` quedan huérfanas.
- **Al terminar**: reiniciar el pod de Valkey para limpiar las keys huérfanas de `/0` (caché regenerable, sin persistencia → sin riesgo).
