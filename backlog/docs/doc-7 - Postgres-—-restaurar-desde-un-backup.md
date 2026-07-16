---
id: doc-7
title: Postgres — restaurar desde un backup
type: guide
created_date: '2026-07-16 20:57'
tags:
  - postgres
  - restore
  - runbook
---
Restaurar **una sola BBDD** desde su dump lógico (`pg_dump` SQL + gzip), sin tocar el resto del clúster. Escenario típico: un upgrade corrompió el esquema de un servicio (p. ej. immich) y hay que volver atrás solo esa BBDD.

El restore se hace con `kubectl` puro disparando el CronJob **suspendido** `postgres-restore`. El script (`postgres.restore.sh`, en ConfigMap) saca los parámetros del **nombre del Job**: `restore-<db>-<selector>`, donde `<selector>` es `latest` o `YYYYMMDD`.

Qué hace el Job automáticamente: guardrail (aborta si la app sigue conectada, salvo `FORCE=yes`) → **dump de seguridad pre-restore** de la BBDD actual → restore atómico (`gunzip | sed(search_path) | psql --single-transaction --set ON_ERROR_STOP=on`) → `REINDEX face_index/clip_index` **solo si la BBDD es immich**.

El Job **solo restaura la BBDD**. Parar y arrancar la app son 2 comandos aparte, derivados por la etiqueta `app=<db>` (sin tabla que mantener).

## 0. Listar qué hay

```bash
ssh nas ls /cold-data/postgres-backups/logical/            # BBDD con dumps
ssh nas ls /cold-data/postgres-backups/logical/<db>/       # dumps de una BBDD
```

## 1. Parar el workload de la app

Convención: BBDD = valor de la etiqueta `app`. Primero míralo:

```bash
kubectl get deploy,sts -A -l app=<db>
```

Escala a 0 todas sus réplicas:

```bash
kubectl get deploy,sts -A -l app=<db> \
  -o jsonpath='{range .items[*]}{.metadata.namespace} {.kind}/{.metadata.name}{"\n"}{end}' \
  | while read ns res; do kubectl -n "$ns" scale "$res" --replicas=0; done
```

> Si `kubectl get -l app=<db>` sale vacío, resuelve el workload a ojo (no todas las apps usan `app=<db>` literal). El guardrail del restore te protege igualmente: aborta si detecta conexiones activas.

## 2. Restaurar

```bash
# último dump disponible:
kubectl -n databases create job restore-<db>-latest --from=cronjob/postgres-restore
# o un día concreto:
kubectl -n databases create job restore-<db>-20260716 --from=cronjob/postgres-restore

kubectl -n databases logs -f job/restore-<db>-latest
```

El Job crea antes un **dump de seguridad pre-restore** en `/cold-data/postgres-backups/logical/<db>/_pre-restore/` (tu deshacer).

## 3. Re-arrancar la app

```bash
kubectl get deploy,sts -A -l app=<db> \
  -o jsonpath='{range .items[*]}{.metadata.namespace} {.kind}/{.metadata.name}{"\n"}{end}' \
  | while read ns res; do kubectl -n "$ns" scale "$res" --replicas=1; done
```

> Ajusta `--replicas` si alguna app corre con N > 1 (aquí todas son single-replica).

## Alternativa: restore sobre «slate limpio» (BBDD recreada desde cero)

Si necesitas partir de una BBDD vacía (no restaurar *sobre* la existente), **NO** hagas un `CREATE DATABASE <app>` a secas: perderías la colación `C`, el `TEMPLATE template0` y las ACLs con las que se crean todas las BBDD del clúster — y **Synapse exige `LC_COLLATE 'C'`**, así que un `CREATE DATABASE` por defecto lo rompería.

En su lugar:

```bash
# 1. Terminar conexiones y borrar la BBDD
kubectl -n databases create job dropdb-<db>-$(date +%s) --from=cronjob/postgres-restore   # (o hazlo con un psql ad-hoc)
#    psql: SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='<db>';
#          DROP DATABASE <db> WITH (FORCE);

# 2. Recrear la BBDD con colación C + extensiones RELANZANDO el Job de create-user:
kubectl -n databases delete job postgres-create-user-<db> --ignore-not-found
argocd app sync postgres --grpc-web    # ArgoCD recrea el Job desde la rama manifests
#    (postgres.create-user.sh crea: ENCODING UTF8 LC_COLLATE C LC_CTYPE C TEMPLATE template0
#     + extensiones vector/vchord/cube/earthdistance + ACLs)

# 3. Restaurar encima (ya con la colación/ACLs correctas):
kubectl -n databases create job restore-<db>-latest --from=cronjob/postgres-restore
```

## Notas y caveats

- **Guardrail**: el restore aborta si la BBDD destino tiene conexiones de cliente activas. Para forzar (con la app aún conectada) añade `FORCE=yes` como env en un Job inline; lo normal es escalar la app a 0 antes.
- **Pre-restore dump**: la carpeta `_pre-restore/` está **excluida del pruner GFS** → **no se poda sola**. Limpia esos dumps de deshacer a mano cuando ya no los necesites (`ssh nas rm .../logical/<db>/_pre-restore/<fichero>`).
- **El dump por-BBDD NO incluye roles/globals** ni las propiedades a nivel de BBDD (colación, template, ACLs). Por eso el restore **in-place** asume que la BBDD y su role ya existen con la colación/permisos correctos.
- **immich y snapper**: las fotos físicas (`/cold-data/immich`) están protegidas por BTRFS+snapper con horizonte ~6 meses, alineado con la retención GFS de estos dumps. Restaurar la BBDD a un punto muy anterior puede referenciar fotos ya podadas por snapper.
- **Verificado** (2026-07-16): restore de immich (con REINDEX vchord) y de un servicio no-immich (authelia, vía genérica sin REINDEX); guardrail aborta con conexiones activas y procede sin ellas; las BBDD recreadas mantienen colación `C`.
