---
id: NASKS-44
title: Añadir backup lógico con pg_dump/pg_dumpall
status: To Do
assignee: []
created_date: '2026-03-22 01:27'
updated_date: '2026-03-28 07:54'
labels:
  - postgres
  - backups
dependencies: []
references:
  - lib/databases/postgres/postgres.libsonnet
  - lib/databases/postgres/postgres.backup.sh
  - lib/databases/postgres/postgres.cleanup.sh
priority: medium
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- SECTION:DESCRIPTION:END -->
