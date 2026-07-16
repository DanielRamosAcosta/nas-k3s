---
id: NASKS-81
title: Backup lógico por BBDD (pg_dump) con retención GFS alineada a snapper
status: In Progress
assignee:
  - Daniel
created_date: '2026-07-16 19:05'
updated_date: '2026-07-16 20:30'
labels: []
dependencies: []
references:
  - lib/databases/postgres/postgres.libsonnet
  - lib/databases/postgres/postgres.backup.sh
  - lib/databases/postgres/postgres.cleanup.sh
  - lib/databases/postgres/postgres.config.conf
  - lib/databases/postgres/postgres.create-user.sh
  - lib/media/immich/immich.libsonnet
  - hosts/nas/snapper.nix (repo infra/system)
  - 'https://immich.app/docs/administration/backup-and-restore'
priority: high
type: enhancement
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Añadir backup lógico por base de datos (`pg_dump`) al clúster Postgres compartido, con retención GFS (7 diarios / 4 semanales / 6 mensuales / 0 anuales) alineada con snapper. Complementa —no sustituye— al `pg_basebackup`+WAL existente, aportando la capacidad que hoy falta: **restaurar una sola app** (p. ej. immich tras una migración que corrompe su esquema) sin tocar el resto del clúster.

## 🎯 Contexto funcional

Escenario disparador: "actualicé immich y se corrompió su BBDD". Hoy no se puede resolver limpiamente.

Estado actual del backup de Postgres (todo va al HDD `/cold-data/postgres-backups`, que es RAID):
- `pg_basebackup` diario (`postgres-base-backup`, 2 AM) → backup **físico de todo el clúster**.
- WAL archiving (`archive_command` → `/backups/wal_archive/`, `archive_timeout=300`) → PITR con RPO ~5 min.
- Cleanup diario (`postgres-backup-cleanup`, 3 AM) con retención por conteo.

Limitación clave: `pg_basebackup` respalda las ~10 BBDD (immich, authelia, grafana, synapse, sftpgo, invidious, facturascripts, crowdsec, wger, mautrixwhatsapp) como **un bloque único** — comparten `PGDATA` (`/data/postgres/data`). No se puede restaurar "solo immich"; o restauras todo el clúster a un punto en el tiempo (haciendo rollback a authelia, grafana, etc.) o nada. Para una corrupción de esquema de UNA app, la herramienta correcta es un **dump lógico por BBDD** (`pg_dump`), que no existe. Es también lo que recomienda la doc oficial de Immich.

Decisiones tomadas en el refinamiento:
- **Mantener** `pg_basebackup`+WAL tal cual: cubre desastre físico del clúster + PITR fino (~última semana). No se toca.
- **Añadir** `pg_dump` por BBDD: cubre restauración granular por-app + historial largo.
- **Retención alineada a snapper y uniforme** para todas las BBDD: 7 diarios / 4 semanales / 6 mensuales / 0 anuales → horizonte ~6 meses. Se alinea deliberadamente con la retención de snapper de immich (8 horarios / 7 diarios / 4 semanales / 6 mensuales, `YEARLY=0` → ~5,5-6 meses reales) para que BBDD y **fotos físicas** tengan el mismo horizonte y una restauración a un punto pasado sea consistente (evitar dumps de BBDD que referencien fotos ya fuera de los snapshots de snapper).
- **Formato de dump = SQL plano + gzip** (`pg_dump --clean --if-exists | gzip`), uniforme para todas las BBDD. NO custom `-Fc`: es el formato que immich soporta oficialmente en su restore, que requiere un `sed` sobre `search_path` solo interceptable en SQL plano (no con `pg_restore`).
- **Descubrimiento dinámico de BBDD**: al añadir una app nueva entra en el backup sola, sin editar el script.

Contexto de almacenamiento (no hace falta cubrirlo aquí):
- Fotos físicas de immich (`/cold-data/immich`): protegidas por **BTRFS RAID + snapper** (config `hosts/nas/snapper.nix`, común a todos los subvolúmenes de `/cold-data`).
- SSD (`/data`, `PGDATA`) y HDD (`/cold-data`) ambos en RAID. `PGDATA` NO tiene snapper (vive en el subvolumen raíz `@`) → su protección es precisamente basebackup+WAL, por eso se mantiene.
- Descartado meter snapper al destino de backups: pinearía los dumps podados y rompería el cleanup por retención (crecimiento sin control), además de ser "backup de un backup" ya cubierto por el RAID.
- Off-site: fuera del alcance de esta tarea.

## ⚙️ Contexto técnico

Ubicación: `lib/databases/postgres/` (mismo patrón que el basebackup existente — `CronJob` + script vía `importstr`).

Piezas a añadir:
1. **`postgres.dump.sh`** (nuevo) — descubre BBDD dinámicamente (`SELECT datname FROM pg_database WHERE NOT datistemplate AND datname != 'postgres'`) y hace `pg_dump --clean --if-exists --dbname <db> | gzip` de cada una a `/cold-data/postgres-backups/logical/<db>/<db>-YYYYMMDD-HHMMSS.sql.gz` (montado en el contenedor como `/backups/logical/...`).
2. **`postgres.dump-prune.sh`** (nuevo) — pruner GFS por conteo, por BBDD: conserva el dump más reciente de cada ciclo (7 diarios / 4 semanales / 6 mensuales / 0 anuales), tiers en una variable configurable al principio del script; `LOGICAL_DIR` overrideable por env var; fecha derivada del nombre del fichero.
3. **CronJob `postgres-logical-dump`** (1 AM) y **CronJob `postgres-logical-prune`** (4 AM, tras el dump) en `postgres.libsonnet`, reutilizando: imagen `versions.postgres`, montaje hostPath `backup-storage` → `/cold-data/postgres-backups`, y el sealed secret de backup existente (`postgres-backup-sealed-secret`, patrón `u.sealedSecret.wide`). Ningún secreto pasa por el contexto.
4. **Restore vía `kubectl` puro** (sin scripts locales): un CronJob **suspendido** `postgres-restore` (pod spec en GitOps) + el script `postgres.restore.sh` (ConfigMap). Se dispara con `kubectl -n databases create job restore-<db>-<latest|YYYYMMDD> --from=cronjob/postgres-restore`; el script saca los parámetros del **nombre del Job** (downward API). Hace dump de seguridad pre-restore + restore sobre la BBDD existente (preserva colación `C`/template/ACLs que el dump por-BBDD no incluye; `gunzip | sed(search_path) | psql --single-transaction --set ON_ERROR_STOP=on`) + `REINDEX face_index/clip_index` **solo si immich**. El Job **solo restaura la BBDD**; parar/arrancar la app son 2 comandos **derivados dinámicamente por la etiqueta `app=<db>`** (sin tabla que mantener). Toda la documentación de uso (crear backup ad-hoc, restaurar) y las skills `postgres/create-backup` + `postgres/restore-backup` van en `backlog/docs` (Fase 4). Alternativa slate-limpio NO usa `CREATE DATABASE` a secas (rompería Synapse, que exige `LC_COLLATE 'C'`) sino que relanza el Job `postgres-create-user-<app>`.

Compatibilidad: `pg_dump` cliente ≥ versión del servidor (ambos PG17, misma imagen). El restore con `--single-transaction --set ON_ERROR_STOP=on` es atómico (rollback si falla). Todas las BBDD del clúster se crean con colación `C` (Synapse lo exige) y llevan las extensiones `vector`/`vchord`/`cube`/`earthdistance` (`create-user.sh:43,64-67`), por lo que el `sed` del `search_path` aplica por igual a todas.

Alcance explícitamente EXCLUIDO: no se modifica `postgres.backup.sh`, `postgres.cleanup.sh`, `postgres.config.conf` (WAL) ni la config de snapper. No se aborda backup off-site.

Referencias de archivos (estado actual):
- `lib/databases/postgres/postgres.libsonnet` — StatefulSet (25-52), montaje `backup-storage`→`/cold-data/postgres-backups` (49,105,125), CronJob basebackup (85-107), CronJob cleanup (110-127), sealed secret backup (80).
- `lib/databases/postgres/postgres.backup.sh` — `pg_basebackup` a `/backups/base` (4).
- `lib/databases/postgres/postgres.config.conf` — WAL archiving (5,9,13).
- `lib/databases/postgres/postgres.create-user.sh` — creación de usuarios/BBDD.
- `lib/media/immich/immich.libsonnet` — conexión a `postgres.databases.svc.cluster.local` (55), user `immich` (56), extensiones vector/vchord (64-67).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Existe un CronJob postgres-logical-dump que hace pg_dump --clean --if-exists comprimido con gzip de todas las BBDD del cluster descubiertas dinamicamente (excluyendo templates y postgres) a /cold-data/postgres-backups/logical/<db>/<db>-YYYYMMDD-HHMMSS.sql.gz
- [ ] #2 Existe un CronJob postgres-logical-prune con retencion GFS 7 diarios / 4 semanales / 6 mensuales / 0 anuales, aplicada por BBDD, con los tiers en una variable configurable del script
- [ ] #3 El basebackup+WAL existente (postgres-base-backup, postgres-backup-cleanup, WAL archiving) no se modifica y sigue operativo
- [x] #4 Ningun secreto pasa por el contexto; se reutiliza el sealed secret de backup existente (postgres-backup-sealed-secret)
- [ ] #5 Restore invocable con kubectl puro (sin scripts locales): CronJob suspendido postgres-restore + script postgres.restore.sh (ConfigMap), disparado con `kubectl create job restore-<db>-<latest|YYYYMMDD> --from=cronjob/postgres-restore` (params tomados del nombre del Job). Hace pre-restore dump de seguridad, restaura (gunzip | sed(search_path) | psql --single-transaction --set ON_ERROR_STOP=on) y REINDEX face_index/clip_index solo si immich; guardrail que aborta si la app sigue conectada salvo FORCE
- [x] #6 Al anadir una BBDD nueva al cluster entra en el backup automaticamente sin editar el script de dump
- [ ] #7 El runbook cubre el caveat de colacion: la alternativa slate-limpio NO usa un CREATE DATABASE a secas (rompe Synapse, que exige LC_COLLATE C) sino que relanza el Job postgres-create-user-<app>; y se valida un restore de un servicio no-immich ademas del de immich
- [ ] #8 En backlog/docs existen dos docs: crear backup ad-hoc (kubectl create job --from=cronjob/postgres-logical-dump) y restaurar desde backup (runbook dinamico por etiqueta app=<db>); y dos skills thin-pointer (postgres/create-backup y postgres/restore-backup) que remiten a cada doc
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Ejecución secuencial fase a fase: implementar UNA fase, desplegar, verificar su checkpoint, y solo entonces pasar a la siguiente. No adelantar código de fases posteriores.

Convenciones comunes (todas las fases):
- Ficheros nuevos en `lib/databases/postgres/`, registrados en `postgres.libsonnet` vía `importstr` + `u.configMap.forFile(...)` y expuestos como claves nuevas del objeto que devuelve `new()` (ArgoCD los recoge solos dentro de la app `postgres` existente; NO hay Application nueva). Reloader no aplica a CronJobs: el siguiente Job monta el ConfigMap ya actualizado.
- Los CronJobs reutilizan: imagen `versions.postgres` (base Debian → trae `pg_dump`/`pg_restore`/`psql`/`gzip` + bash + GNU coreutils/`date`), montaje hostPath `backup-storage` (`/cold-data/postgres-backups`) en `/backups`, scripts montados en `/mnt/scripts` con `u.volumeMount.fromFile(...)`, y el sealed secret `backupSecrets` (`PGPASSWORD`, patrón del basebackup). Conexión SIEMPRE explícita (sin `-h` iría a socket local inexistente → fallo): `-h postgres.databases.svc.cluster.local -p 5432 -U postgres` (superusuario, igual que el basebackup → puede hacer pg_dump de TODAS las BBDD sin problema de permisos). Ningún secreto pasa por el contexto.
- **Formato de dump = SQL plano comprimido con gzip** (`pg_dump --clean --if-exists | gzip`), NO custom `-Fc`. Es el formato que immich soporta oficialmente en su restore (el restore de immich requiere un `sed` sobre `search_path` que solo es interceptable en SQL plano, no con `pg_restore`). Se usa uniforme para todas las BBDD.
- Destino de los dumps: `/backups/logical/<db>/<db>-YYYYMMDD-HHMMSS.sql.gz` (= `/cold-data/postgres-backups/logical/...` en el host).
- **Hechos de aprovisionamiento del clúster que aplican a TODAS las BBDD** (de `postgres.create-user.sh`, no solo immich; importan en el restore): (a) **toda** BBDD se crea con `ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0` (línea 43) — Synapse **exige** colación `C`, y aquí es el default del clúster; (b) **toda** BBDD lleva las extensiones `vector`/`vchord`/`cube`/`earthdistance` (líneas 64-67), así que el `sed` sobre `search_path` en el restore aplica por igual a todas, no solo a immich; (c) hay ACLs a nivel de BBDD (`REVOKE CONNECT ... FROM PUBLIC`, `GRANT CONNECT ... TO <app>`, líneas 49-59). Un `pg_dump` por-BBDD **NO** incluye ni roles/globals ni estas propiedades a nivel de BBDD (colación, template, ACLs) → el restore asume que el role del app ya existe y **prefiere restaurar SOBRE la BBDD existente** (que ya tiene colación/ACLs correctas), no recrearla.
- Desplegar SIEMPRE con la skill `/deploy` (commit+push a main → CI exporta a rama `manifests` → ArgoCD sincroniza solo). Verificar logs vía Loki (MCP `grafanaSelfHosted`), NUNCA `kubectl logs`.
- Disparo manual de un CronJob (nombre literal, no lo altera `labelApp`): `kubectl -n databases create job --from=cronjob/<nombre> <nombre>-manual-1`.

---

## Fase 1 — CronJob de dump (`postgres-logical-dump`)

1. Crear `lib/databases/postgres/postgres.dump.sh` (`#!/bin/bash`, `set -euo pipefail`; además `set -o pipefail` ya cubierto → comprobar fallo del pipe pg_dump|gzip):
   - `PGHOST=postgres.databases.svc.cluster.local`, `PGPORT=5432`, `LOGICAL_DIR="/backups/logical"`. (`PGPASSWORD` viene del entorno vía `backupSecrets`.)
   - Descubrir BBDD dinámicamente: `DBS=$(psql -h "$PGHOST" -p "$PGPORT" -U postgres -Atc "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname NOT IN ('postgres')")`.
   - Para cada `db`: `mkdir -p "$LOGICAL_DIR/$db"` y `pg_dump -h "$PGHOST" -p "$PGPORT" -U postgres --clean --if-exists --dbname "$db" | gzip > "$LOGICAL_DIR/$db/$db-$(date +%Y%m%d-%H%M%S).sql.gz"`. Con `pipefail`, un fallo de pg_dump aborta y no deja un `.sql.gz` "válido" a medias (considerar escribir a `.tmp` y `mv` al final para atomicidad). Log por BBDD (inicio/fin/tamaño con `du -h`).
2. En `postgres.libsonnet`: añadir `local dumpScript = importstr './postgres.dump.sh';`, la clave `dumpScriptConfigMap: u.configMap.forFile('postgres.dump.sh', dumpScript),` y el CronJob `logicalDumpCron` (patrón calcado de `baseBackupCron`: imagen `versions.postgres`, command `['/bin/bash', '/mnt/scripts/postgres.dump.sh']`, env `u.envVars.fromSealedSecret(self.backupSecrets)`, volúmenes `backup-storage` + configmap del script, `restartPolicy OnFailure`, `concurrencyPolicy Forbid`, history limits 3/3). Schedule `0 1 * * *` (1 AM, antes del basebackup de las 2 AM; `Forbid` solo evita solapes del mismo CronJob, no comparte lock con el basebackup → un dump que cruce las 2 AM es inocuo).
3. Validar compilación: `tk eval environments/databases | jq '.'` sin errores.
4. **Desplegar** con la skill `/deploy`.
5. **Checkpoint Fase 1**: disparo manual `kubectl -n databases create job --from=cronjob/postgres-logical-dump dump-manual-1`. Verificar en Loki (`{namespace="databases", pod=~"dump-manual-1.*"}`) que recorre todas las BBDD sin error, y en el NAS (`ssh nas`) que existen `<db>-*.sql.gz` en `/cold-data/postgres-backups/logical/<db>/` para cada BBDD. Confirmar tamaño > 0 y que descomprime sin error (`gunzip -t`) el de immich. Nota: verificar que `gzip`/`gunzip` existen en la imagen `versions.postgres` (la de immich es Debian → `gzip` es prioridad `required`, debería estar; si no, fallback `pg_dump -Z` NO sirve porque rompe el `sed` del restore → habría que reconsiderar la imagen). Es lo primero a comprobar en este checkpoint porque condiciona también la Fase 3.

---

## Fase 2 — CronJob de prune GFS (`postgres-logical-prune`)

1. Crear `lib/databases/postgres/postgres.dump-prune.sh` (`#!/bin/bash`, `set -euo pipefail`; corre con imagen `versions.postgres` por su bash + GNU `date`):
   - `LOGICAL_DIR="${LOGICAL_DIR:-/backups/logical}"` — **overrideable por env var** para apuntarlo a una carpeta de prueba en el checkpoint sin tocar los dumps reales.
   - Tiers configurables al principio: `KEEP_DAILY=7`, `KEEP_WEEKLY=4`, `KEEP_MONTHLY=6`, `KEEP_YEARLY=0`.
   - **Invariante de carpetas** (contrato con la Fase 3): el pruner itera SOLO las subcarpetas de primer nivel de `$LOGICAL_DIR` que **no** empiecen por `_` (reservados: `_pre-restore`, `_gfstest`) y lista SOLO `$db/*.sql.gz` del primer nivel (glob de shell, **sin** recursión / sin `find`). Así nunca toca los dumps de seguridad pre-restore (que viven en `$db/_pre-restore/`) ni las carpetas de prueba.
   - Algoritmo GFS por conteo, por BBDD (estilo restic/borg forget): por cada carpeta-BBDD válida, listar los `*.sql.gz` ordenados de más nuevo a más viejo. La **fecha se deriva del NOMBRE del fichero** (`-YYYYMMDD-HHMMSS`), NUNCA de mtime (`date -d "YYYY-MM-DD"`). Recorrer nuevo→viejo y marcar "conservar" el más reciente de cada bucket hasta agotar el límite de su tier: diario `%Y%m%d` (hasta 7), semanal ISO `%G-%V` (hasta 4), mensual `%Y%m` (hasta 6), anual `%Y` (0 → ninguno). Un dump se conserva si entra en al menos un tier. **Desempate mismo bucket**: al recorrer nuevo→viejo, el primero que cae en un bucket lo "cubre"; los siguientes del mismo bucket → DELETE salvo que entren por otro tier aún no lleno (esto maneja varios dumps el mismo día, p. ej. por disparos manuales `dump-manual-*`). Nota: con dumps diarios los tiers se solapan → el conjunto conservado es < 7+4+6. Borrar los no conservados. Log claro por fichero (`KEEP`/`DELETE` + tier que lo justifica).
2. En `postgres.libsonnet`: añadir `local pruneScript = importstr './postgres.dump-prune.sh';`, la clave `pruneScriptConfigMap: u.configMap.forFile('postgres.dump-prune.sh', pruneScript),` y el CronJob `logicalPruneCron` (patrón de `cleanupCron` pero imagen `versions.postgres` en vez de busybox, porque el pruner usa GNU `date`). Command `['/bin/bash', '/mnt/scripts/postgres.dump-prune.sh']`. Schedule `0 4 * * *` (4 AM: margen amplio tras el dump de la 1 AM para que un dump largo haya terminado; da igual si no, el dump del día en curso siempre es el más nuevo → KEEP). Volúmenes: `backup-storage` + configmap del pruner. `restartPolicy OnFailure`, `concurrencyPolicy Forbid`.
3. Validar compilación con `tk eval`.
4. **Desplegar** con la skill `/deploy`.
5. **Checkpoint Fase 2**:
   - a) Disparo manual `kubectl -n databases create job --from=cronjob/postgres-logical-prune prune-manual-1`. Con pocos dumps (1-2 por BBDD) debe ser no-op: en Loki, todos `KEEP` y ninguno `DELETE`; confirmar en el NAS que los `.sql.gz` siguen ahí.
   - b) Prueba del algoritmo GFS sin tocar los dumps reales: en el NAS crear `/cold-data/postgres-backups/logical/_gfstest/<db>/` con ficheros sintéticos `touch _gfstest-YYYYMMDD-000000.sql.gz` abarcando ~8 meses de fechas variadas (varias por semana; incluir 2 el mismo día para probar el desempate). Correr el pruner con `LOGICAL_DIR=/cold-data/postgres-backups/logical/_gfstest` (env var en un pod ad-hoc o ejecutando el script en el NAS). Verificar que conserva **1 por bucket hasta el límite de cada tier con los solapes esperados** (no un conteo fijo de 17) y borra el resto, revisando el log `KEEP`/`DELETE`. Eliminar `_gfstest` al terminar.

---

## Fase 3 — Mecanismo de restore (`kubectl create job --from`)

Restaurar = un `kubectl` puro, sin scripts locales. Un **CronJob suspendido** (`postgres-restore`) lleva todo el pod spec en GitOps; se dispara con `kubectl create job restore-<db>-<selector> --from=cronjob/postgres-restore`, y el script saca los parámetros **del nombre del Job**. El Job **solo restaura la BBDD**; parar/arrancar la app son 2 comandos (derivados por etiqueta `app=<db>`, sin tabla) que se documentan en la Fase 4. Esta fase entrega el **mecanismo**; la **documentación de uso y las skills van en la Fase 4**.

1. Crear `lib/databases/postgres/postgres.restore.sh` (ConfigMap gestionado por GitOps). Resolución de parámetros (env tiene prioridad sobre el nombre, para poder testear con override):
   - `TARGET_DB`: si el env está vacío, parsear del **nombre del pod** vía downward API (`fieldRef: metadata.name` → `POD_NAME`, siempre disponible; se prefiere a la etiqueta `job-name` cuya clave varía entre versiones — `batch.kubernetes.io/job-name` en k8s recientes). El pod es `restore-<db>-<selector>[-<hash>]` → `IFS=- read -r _ TARGET_DB DUMP_SEL _ <<<"$POD_NAME"` (nombres de BBDD = un solo token sin guiones, y el hash final del pod cae en el campo descartado → robusto).
   - `SOURCE_DB` = `${SOURCE_DB:-$TARGET_DB}` (permite dump de una BBDD dentro de otra distinta en tests). REINDEX de vchord se decide por `SOURCE_DB == immich`.
   - `DUMP_SEL` (`latest` o `YYYYMMDD`): `latest` → `ls -1 "$LOGICAL_DIR/$SOURCE_DB"/*.sql.gz | sort | tail -1`; una fecha → `...*-$DUMP_SEL-*.sql.gz | sort | tail -1` (primer nivel, por nombre — no alcanza `_pre-restore/`).
   - **Guardrails**: abortar si `TARGET_DB` vacío; **abortar si hay conexiones externas** a `TARGET_DB`, evaluado ANTES del pre-restore dump: `SELECT count(*) FROM pg_stat_activity WHERE datname='$TARGET_DB' AND pid <> pg_backend_pid() AND backend_type = 'client backend'` > 0 → salvo `FORCE=yes`. NO depender de `application_name` (las apps lo dejan vacío; contarse a sí mismo abortaría siempre) — de ahí `pid <> pg_backend_pid()`.
   - Pasos: (a) **dump de seguridad pre-restore** de la BBDD destino actual a `/backups/logical/$TARGET_DB/_pre-restore/$TARGET_DB-<ts>.sql.gz` (undo). `_pre-restore/` está **excluida del pruner GFS** (invariante `_` de la Fase 2) → **no se poda sola**: documentar limpieza manual (o retención propia simple). (b) restore: `gunzip -c "$DUMP_FILE" | sed "$SEARCH_PATH_SED" | psql -U postgres -d "$TARGET_DB" --single-transaction --set ON_ERROR_STOP=on`, con `SEARCH_PATH_SED` = patrón **literal completo** `s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g` (load-bearing; no abreviar). (c) si `SOURCE_DB=immich`: `REINDEX INDEX face_index; REINDEX INDEX clip_index;`. Logging ruidoso.
   - En `postgres.libsonnet`: `local restoreScript = importstr './postgres.restore.sh';` + `restoreScriptConfigMap: u.configMap.forFile('postgres.restore.sh', restoreScript),`.
2. Crear el **CronJob suspendido** `restoreCron` en `postgres.libsonnet` (molde reutilizable; NO se ejecuta solo): `cronJob.new('postgres-restore', schedule='0 0 31 2 *', ...)` (fecha imposible, 31-feb — belt-and-suspenders) + `cronJob.spec.withSuspend(true)`. Pod spec calcado del patrón backup: imagen `versions.postgres`, `command: [/bin/bash, /mnt/scripts/postgres.restore.sh]`, env `u.envVars.fromSealedSecret(self.backupSecrets)` (`PGPASSWORD`) + `POD_NAME` vía downward API (`valueFrom.fieldRef.fieldPath: metadata.name`), volúmenes `backup-storage` (hostPath) + el ConfigMap del restore, `restartPolicy: Never`, `concurrencyPolicy: Forbid`, history limits. Se dispara con `kubectl -n databases create job restore-<db>-<latest|YYYYMMDD> --from=cronjob/postgres-restore` (nombre único → si colisiona, sufijo extra que el parser ignora). Los Jobs creados con `--from` NO llevan la anotación de tracking de ArgoCD → ArgoCD no los adopta/prunea (solo el CronJob suspendido es recurso gestionado).
3. Validar compilación (`tk eval`) — el CronJob suspendido y el ConfigMap.
4. **Desplegar** con la skill `/deploy`. ArgoCD publica el ConfigMap + el CronJob **suspendido** (`suspend: true` → nunca se ejecuta en un sync; solo cuando tú lanzas un `create job --from`).
5. **Checkpoint Fase 3** (verificación real, no destructiva): confirmar espacio en `/data` (`ssh nas df -h /data`) y horario tranquilo.
   - **Restore normal por la vía real**: `kubectl -n databases create job restore-<db>-latest --from=cronjob/postgres-restore` NO es no-destructivo (restaura sobre la BBDD real). Para el test no destructivo, lanzar un Job **inline** (heredoc) del mismo pod spec pero con env override `TARGET_DB=immich_restore_test SOURCE_DB=immich DUMP_FILE=latest FORCE=yes` (el override por env es justo para esto). Previo: `createdb -U postgres immich_restore_test` con `LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0`.
   - Verificar en los logs: pre-restore dump creado, restore sin error, y REINDEX (por `SOURCE_DB=immich`) pasa OK (no basta `count(*) FROM assets`: valida que los índices vchord quedan reconstruibles). `\dt | head` y `SELECT count(*) FROM assets`. Luego `dropdb immich_restore_test`.
   - Repetir con un servicio **no-immich** (`SOURCE_DB=authelia`, temp con colación `C`) → vía genérica **sin** REINDEX.
   - Guardrail — ambos casos: (i) con la app arrancada (conexiones activas) → **aborta** sin `FORCE`; (ii) BBDD de prueba sin conexiones → **procede** (verifica que `pid <> pg_backend_pid()` no se autocuenta).
   - AC#7 al 100%: ejercitar de verdad el relanzado de `postgres-create-user-<app>` contra una BBDD temporal borrada y comprobar que la recrea con colación `C` + extensiones antes de restaurar.
   - Verificar además que un Job lanzado con `--from` **no** es prunado por ArgoCD (no lleva su anotación de tracking).

---

## Fase 4 — Documentación (backlog/docs) + skills

Toda la documentación de uso y las skills. Docs en `backlog/docs` (vía MCP `mcp__backlog__document_create`); skills en `.claude/skills/` (formato del repo: frontmatter `name`/`description`/`allowed-tools` + cuerpo markdown, ver `save`/`deploy`). **No requiere `/deploy`** (no son recursos del clúster; son ficheros del repo/backlog).

1. **Doc "Postgres — crear un backup ad-hoc"** (`backlog/docs`): forzar un backup inmediato (p. ej. antes de subir una major de un servicio). Mecanismo, sin código nuevo: disparar el CronJob de dump existente — `kubectl -n databases create job manual-backup-$(date +%s) --from=cronjob/postgres-logical-dump` → dump fresco de TODAS las BBDD al store lógico (incluida la del servicio a actualizar). Seguir con `kubectl -n databases logs -f job/manual-backup-<ts>`; verificar el `.sql.gz` nuevo en el NAS. Nota: el GFS conserva el del día en curso (el más nuevo → KEEP), así que sirve de red antes del upgrade.
2. **Doc "Postgres — restaurar desde un backup"** (`backlog/docs`): el runbook dinámico completo (movido desde la antigua Fase 3), todo por etiqueta `app=<db>`, sin tabla que mantener:
   - Listar BBDDs/dumps: `ssh nas ls /cold-data/postgres-backups/logical/` y `.../logical/<db>/`.
   - (1) Parar el workload: `kubectl get deploy,sts -A -l app=<db>` para verlo; escalar a 0 con `kubectl get deploy,sts -A -l app=<db> -o jsonpath='{range .items[*]}{.metadata.namespace} {.kind}/{.metadata.name}{"\n"}{end}' | while read ns res; do kubectl -n "$ns" scale "$res" --replicas=0; done`.
   - (2) Restaurar: `kubectl -n databases create job restore-<db>-latest --from=cronjob/postgres-restore` (o `restore-<db>-YYYYMMDD`); `kubectl -n databases logs -f job/restore-<db>-latest`.
   - (3) Re-arrancar: mismo one-liner con `--replicas=1` (single-replica; ajustar si alguna tuviera N).
   - Convención BBDD = etiqueta `app` (si `kubectl get -l app=<db>` sale vacío, resolver a ojo — sin tabla que se desactualice).
   - **Alternativa "slate limpio"**: NO `CREATE DATABASE <app>` a secas (perdería colación `C`/template/ACLs → rompe Synapse) → `pg_terminate_backend(...)` + `DROP DATABASE <app> WITH (FORCE);` + **relanzar `postgres-create-user-<app>`** + restaurar.
   - Notas: el pre-restore dump (`_pre-restore/`) no se poda solo (limpieza manual); el dump por-BBDD no incluye roles/globals (restore in-place asume role existente); aviso immich de fotos podadas por snapper (~6 meses).
3. **Skill `postgres/create-backup`**: thin pointer que solo remite a la doc 1. `SKILL.md` con `description` clara ("crear un backup ad-hoc de Postgres antes de un cambio de riesgo") y cuerpo que dice "lee y sigue la doc «Postgres — crear un backup ad-hoc» de `backlog/docs` (`mcp__backlog__document_view`)". (Nombre/ubicación exactos —`postgres/create-backup` vs `postgres-create-backup`— confirmar según el discovery de skills; ver `save`.)
4. **Skill `postgres/restore-backup`**: thin pointer análogo que remite a la doc 2.
5. **Checkpoint Fase 4**: las dos docs existen en `backlog/docs` y se abren con `mcp__backlog__document_view`; invocar `/postgres/create-backup` y `/postgres/restore-backup` carga la skill y remite a la doc correcta. (Sin despliegue.)

---

## Cierre

- Marcar los AC conforme se cumplen. Confirmar con el usuario antes de `Done`.
- Alcance EXCLUIDO (no tocar): `postgres.backup.sh`, `postgres.cleanup.sh`, `postgres.config.conf` (WAL), config de snapper, backup off-site.
<!-- SECTION:PLAN:END -->
