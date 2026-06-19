---
id: NASKS-62
title: Separar Immich y ArgoCD en DBs lógicas distintas de Valkey (colisión en /0)
status: To Do
assignee: []
created_date: '2026-05-08 06:01'
updated_date: '2026-06-19 16:56'
labels:
  - databases
  - tech-debt
dependencies: []
priority: low
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- SECTION:DESCRIPTION:END -->
