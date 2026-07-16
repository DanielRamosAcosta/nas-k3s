---
id: doc-6
title: Postgres — crear un backup ad-hoc
type: guide
created_date: '2026-07-16 20:57'
tags:
  - postgres
  - backup
  - runbook
---
Forzar un backup lógico inmediato de **todas** las BBDD del clúster Postgres, p. ej. como red de seguridad justo antes de subir una versión mayor de un servicio (immich, synapse, etc.).

No hace falta código nuevo: se dispara a mano el CronJob de dump existente (`postgres-logical-dump`), que descubre las BBDD dinámicamente y escribe un `pg_dump --clean --if-exists | gzip` por cada una en `/cold-data/postgres-backups/logical/<db>/<db>-YYYYMMDD-HHMMSS.sql.gz`.

## Cuándo usarlo

- Antes de un upgrade de riesgo de un servicio (migración de esquema que podría corromper su BBDD).
- Antes de cualquier operación manual sobre una BBDD.

Para restaurar, ver la guía **«Postgres — restaurar desde un backup»**.

## Pasos

1. Disparar un dump inmediato de todas las BBDD:

   ```bash
   kubectl -n databases create job manual-backup-$(date +%s) --from=cronjob/postgres-logical-dump
   ```

2. Seguir el progreso (recorre todas las BBDD, una línea `listo (<tamaño>)` por cada una):

   ```bash
   kubectl -n databases logs -f job/manual-backup-<ts>
   ```

   > Los logs también están en Loki: `{namespace="databases", pod=~"manual-backup-.*"}`.

3. Verificar que el nuevo `.sql.gz` existe (opcional):

   ```bash
   ssh nas ls -lh /cold-data/postgres-backups/logical/<db>/
   ```

## Notas

- El dump es de **todas** las BBDD, no solo la del servicio que vas a tocar — es lo esperado y barato.
- El pruner GFS (`postgres-logical-prune`, 4 AM) siempre conserva el dump **del día en curso** (es el más nuevo → `KEEP`), así que el backup ad-hoc sobrevive como red antes del upgrade.
- Al terminar, el Job queda en el historial (`successfulJobsHistoryLimit`); no hace falta borrarlo a mano.
