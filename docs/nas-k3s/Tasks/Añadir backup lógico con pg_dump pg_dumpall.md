---
title: Añadir backup lógico con pg_dump/pg_dumpall
status: Done
created_date: '2026-03-22 01:27'
labels:
  - postgres
  - backups
dependencies: []
references:
  - lib/databases/postgres/postgres.libsonnet
  - lib/databases/postgres/postgres.backup.sh
  - lib/databases/postgres/postgres.cleanup.sh
priority: 2
ordinal: 53000
---

## Description

Actualmente solo tenemos backups físicos (pg_basebackup + WAL archiving) que requieren montar una instancia temporal de PostgreSQL para restaurar una sola base de datos. Añadir un CronJob con `pg_dumpall` o `pg_dump` por base de datos para tener dumps lógicos (SQL) que permitan restaurar selectivamente una DB, un usuario o una tabla sin PITR.

### Contexto
- Los backups físicos actuales ocupan ~1.3 GB por snapshot (cluster entero)
- Para recuperar una sola DB hay que hacer PITR completo con docker + WAL replay
- Un dump lógico permite `psql < dump.sql` directamente, mucho más simple

### Decisiones a tomar
- `pg_dumpall` (un solo fichero con todo) vs `pg_dump` por cada base de datos (más granular, restauración independiente)
- Formato: SQL plano vs custom (`-Fc`, permite `pg_restore` selectivo por tabla)
- Retención: ¿misma que base backups (7 días)?
- Destino: `/cold-data/postgres-backups/logical/` junto a los backups físicos
- Compresión: gzip o usar compresión nativa de pg_dump

## Implementation Notes

Superada e implementada por la tarea [[Backup lógico por BBDD (pg_dump) con retención GFS alineada a snapper]] (Done, 2026-07-16). Resolución de las decisiones abiertas:

- `pg_dump` **por BBDD** (no `pg_dumpall`): permite restaurar una sola DB sin tocar el resto del clúster. Descubrimiento dinámico de BBDD (excluye templates y `postgres`).
- Formato SQL plano + gzip, con `--clean --if-exists`.
- Retención **GFS** (daily=7, weekly=4, monthly=6) alineada con snapper, no los 7 días fijos del base backup.
- Implementación: `postgres.dump.sh` + `postgres.dump-prune.sh`, CronJobs `postgres-logical-dump` (1 AM) y `postgres-logical-prune` (4 AM) en `postgres.libsonnet`. Skills `postgres-create-backup` / `postgres-restore-backup` operativas.
