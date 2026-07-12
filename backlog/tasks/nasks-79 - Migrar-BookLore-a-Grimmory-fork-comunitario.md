---
id: NASKS-79
title: Migrar BookLore a Grimmory (fork comunitario)
status: To Do
assignee: []
created_date: '2026-07-10 20:43'
labels:
  - media
  - migration
dependencies: []
references:
  - 'https://github.com/grimmory-tools/grimmory'
  - 'https://github.com/orgs/grimmory-tools/discussions/120'
  - 'https://github.com/grimmory-tools/grimmory/blob/develop/README.md'
priority: medium
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Migrar el despliegue de BookLore a **Grimmory**, el fork comunitario mantenido tras el borrado abrupto del proyecto original por su maintainer. La migración es un drop-in: swap de imagen en `lib/versions.json`; la DB de MariaDB se auto-migra en el primer arranque.

## 🎯 Contexto funcional

A mediados de marzo de 2026 el maintainer de BookLore (adityachandelgit) borró deliberadamente todo el proyecto (repo de GitHub, Discord, web) sin aviso de deprecación, baneando a quien lo mencionara. El trasfondo incluía acusaciones de telemetría opaca, un cliente de pago recortando features del free y la insinuación de un cambio de licencia retroactivo. BookLore quedó sin mantenimiento y salió del catálogo de TrueNAS.

Ex-contribuidores crearon **Grimmory** (`grimmory-tools/grimmory`, AGPL-3.0), un fork activo con releases regulares, pensado como reemplazo drop-in. Migrar nos devuelve a un proyecto mantenido sin perder la biblioteca, usuarios ni progreso de lectura existentes.

## ⚙️ Contexto técnico

Estado actual del despliegue (`lib/media/booklore/booklore.libsonnet`):
- Deployment `booklore`, imagen `booklore/booklore:v2.2.1` (pin en `lib/versions.json`).
- DB: MariaDB compartida (`mariadb.databases.svc.cluster.local`), base `booklore`, usuario `booklore`.
- Volúmenes hostPath: `/cold-data/booklore/{data,books,bookdrop}`.
- Puerto 6060, startup probe `/api/v1/healthcheck`, IngressRoute `books.danielramos.me`.
- Login vía OIDC con Authelia.

Mecanismo de migración (confirmado en la guía oficial, Discussion #120 y README de Grimmory):
- La migración es un **swap de imagen**: cambiar en `lib/versions.json` la imagen de `booklore/booklore` a `grimmory/grimmory` (o `ghcr.io/grimmory-tools/grimmory`) y el tag a la última release estable pinneada.
- El resto del despliegue (service name, DB/usuario, puertos, volúmenes hostPath, IngressRoute, OIDC) se mantiene sin cambios.
- La **DB de MariaDB se auto-migra en el primer arranque** (mismo formato de esquema); no hay pasos manuales de migración de datos.
- Backup previo recomendado: DB `booklore` y volumen `/cold-data/booklore/data`.
- Avisos de la comunidad (no aplican / a verificar): `DISK_TYPE=NETWORK` deshabilita operaciones de fichero en mounts NFS/SMB → no aplica, el volumen es hostPath local. Kobo Sync tenía incidencias con `kepubify` en setups no docker-compose → verificar si se usa.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lib/versions.json apunta a la imagen de Grimmory (grimmory/grimmory o ghcr.io/grimmory-tools/grimmory) con un tag de versión estable pinneado (no latest)
- [ ] #2 El resto del despliegue se mantiene sin cambios: service name booklore, DB/usuario booklore, puerto 6060, volúmenes hostPath /cold-data/booklore/* e IngressRoute books.danielramos.me
- [ ] #3 Se realiza backup previo de la DB MariaDB booklore y del volumen /cold-data/booklore/data antes del swap
- [ ] #4 Tras el deploy el pod arranca sano (startup probe /api/v1/healthcheck en 6060 OK) y la biblioteca existente (libros, usuarios, progreso) se ve intacta en la UI, confirmando la auto-migración de la DB
- [ ] #5 El login OIDC vía Authelia sigue funcionando tras la migración
- [ ] #6 Se deja constancia de que DISK_TYPE=NETWORK no aplica (volumen hostPath local) y de la referencia a la guía oficial de transición (#120)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Migración por etapas con ciclos cortos: primero backup, luego swap drop-in a una versión cercana a la actual (v2.2.4, validada en la guía #120) para aislar que el fork arranca sin tocar esquema, y por último bump a la última estable (v3.2.4) donde se aplican las migraciones de esquema mayores. Cada fase con despliegue termina en su paso `/deploy` + checkpoint antes de continuar.

Contexto de versiones: BookLore actual = `booklore/booklore:v2.2.1`. Grimmory última estable = `v3.2.4` (2026-07-01). La discusión oficial #120 valida `grimmory/grimmory:v2.2.4` como drop-in directo desde BookLore v2.2.x. Env vars, puerto (6060) y healthcheck (`/api/v1/healthcheck`) son idénticos entre ambos.

### Fase 0 — Verificación previa (sin cambios; evita retrabajo)

Objetivo: confirmar imagen/tags y compatibilidad de env vars **antes** de tocar nada, para no descubrir un `ImagePullBackOff` o una env var renombrada a mitad del deploy.

1. Imagen y tags (ya verificado con skopeo — ambos registries sirven los dos tags):
   ```bash
   skopeo list-tags docker://docker.io/grimmory/grimmory | jq -r '.Tags[]' | grep -E '^v(2\.2\.4|3\.2\.4)$'
   ```
   Imagen canónica a usar: `grimmory/grimmory` (Docker Hub, mismo estilo bare-name que la actual `booklore/booklore`). Alternativa equivalente: `ghcr.io/grimmory-tools/grimmory`.
2. Compatibilidad de env vars (verificado contra el README de Grimmory):
   - Idénticas y sin cambios: `DATABASE_URL`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `USER_ID`, `GROUP_ID`, `TZ`.
   - Puerto: Grimmory ya no usa `BOOKLORE_PORT`, pero su **puerto interno por defecto sigue siendo 6060** → aunque la env var quede ignorada, el contenedor escucha en 6060 (probe y service intactos). No requiere cambios.
   - Cosmético (no bloqueante): Grimmory usa `API_DOCS_ENABLED` en vez de `SPRINGDOC_API_DOCS_ENABLED`/`SPRINGDOC_SWAGGER_UI_ENABLED`. Solo afecta a si se exponen los API docs; se puede dejar como está y, si se quiere limpiar, renombrar en el ConfigMap en una fase posterior (no es parte del scope mínimo).

**Checkpoint Fase 0:** los dos tags aparecen en el listado de skopeo y no hay ninguna env var **obligatoria** nueva que falte en el ConfigMap/Secret actuales.

### Fase 1 — Backup de seguridad (sin cambios en el despliegue)

Objetivo: tener un punto de restauración de la DB y del volumen de datos antes de tocar nada. No hay deploy en esta fase.

1. Asegurar el túnel al clúster si hace falta: `ssh -fN -L 6443:localhost:6443 nas`.
2. Confirmar el nombre de la env var de root de MariaDB **sin exponer su valor** (linuxserver/mariadb usa `MYSQL_ROOT_PASSWORD`):
   ```bash
   kubectl exec -n databases mariadb-0 -- printenv | grep -o '^MYSQL_ROOT_PASSWORD='
   ```
   Debe imprimir solo `MYSQL_ROOT_PASSWORD=` (la clave, sin el valor). Si el nombre difiere, ajústalo en el paso siguiente.
3. Confirmar que el binario de dump existe en la imagen (linuxserver/mariadb 11.4 trae `mariadb-dump`):
   ```bash
   kubectl exec -n databases mariadb-0 -- command -v mariadb-dump
   ```
4. Dump lógico de la base `booklore` (la contraseña se resuelve **dentro** del pod vía `$MYSQL_ROOT_PASSWORD`, nunca entra en el contexto). El `>` redirige a un fichero **en la máquina local** que ejecuta `kubectl`, no dentro del pod:
   ```bash
   kubectl exec -n databases mariadb-0 -- \
     bash -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --databases booklore' \
     > /tmp/booklore-backup.sql
   ```
5. Backup del volumen de datos en el host del NAS (a un tar comprimido en cold-data):
   ```bash
   ssh nas 'sudo tar czf /cold-data/booklore-migration-backup.tar.gz -C /cold-data/booklore data'
   ```

**Checkpoint Fase 1:**
- (local) `/tmp/booklore-backup.sql` existe y no está vacío: `test -s /tmp/booklore-backup.sql` y el fichero termina con `-- Dump completed`.
- (remoto, en el NAS) el tar existe con tamaño > 0: `ssh nas 'ls -lh /cold-data/booklore-migration-backup.tar.gz'`.

### Fase 2 — Swap drop-in a Grimmory v2.2.4

Objetivo: confirmar que el fork arranca como reemplazo directo, sin migración de esquema mayor. Solo cambia la imagen.

1. Editar `lib/versions.json`, entrada `booklore` (líneas 62-65):
   ```json
   "booklore": {
     "image": "grimmory/grimmory",
     "version": "v2.2.4"
   },
   ```
   (Se mantiene la clave `booklore` como identificador interno del módulo; solo cambian `image` y `version`. El customManager de Renovate seguirá trackeando la imagen automáticamente.)
2. Compilar para validar que Jsonnet genera bien y que solo cambia la imagen:
   ```bash
   tk eval environments/media | jq '.booklore.deployment.spec.template.spec.containers[0].image'
   ```
   Debe devolver `"grimmory/grimmory:v2.2.4"`. El resto del manifiesto (service, volúmenes, ingress, env) no debe cambiar.
3. **Desplegar** con la skill `/deploy` (commit + push a main → CI exporta a `manifests` → ArgoCD sincroniza solo → Reloader/rollout del pod).

**Checkpoint Fase 2:**
- Pod `booklore` en `media` en estado `Running` y `Ready` con la nueva imagen (`kubectl get pod -n media -l app=booklore -o jsonpath='{.items[0].spec.containers[0].image}'`).
- Startup probe OK (sin CrashLoop). Revisar arranque vía Loki: `{namespace="media", pod=~"booklore.*"} |~ "(?i)started|error|fail"` — no debe haber errores fatales de arranque/DB.
- En la UI (`books.danielramos.me`): biblioteca, usuarios y progreso de lectura intactos.
- Login OIDC vía Authelia funciona.

### Fase 3 — Bump a la última estable (v3.2.4)

Objetivo: llevar el despliegue a la versión mantenida al día; aquí es donde se aplican las migraciones de esquema mayores (v2 → v3) sobre la DB, respaldada por el backup de la Fase 1.

1. Editar `lib/versions.json`, entrada `booklore`, subir el tag:
   ```json
   "booklore": {
     "image": "grimmory/grimmory",
     "version": "v3.2.4"
   },
   ```
2. Compilar y verificar el tag:
   ```bash
   tk eval environments/media | jq '.booklore.deployment.spec.template.spec.containers[0].image'
   ```
   Debe devolver `"grimmory/grimmory:v3.2.4"`.
3. **Desplegar** con la skill `/deploy`.

> Nota operativa: el customManager de Renovate (`renovate.json`) trackea cualquier imagen de `versions.json`, así que tras la Fase 2 puede abrir un PR de bump a `v3.2.4` por su cuenta. Si aparece antes de ejecutar esta fase a mano, sirve igual — es el mismo destino; solo verifica el checkpoint antes de mergearlo.

**Checkpoint Fase 3:**
- Pod `booklore` `Running`/`Ready` con imagen `grimmory/grimmory:v3.2.4`.
- Logs de arranque vía Loki muestran las migraciones de esquema aplicadas sin error (`{namespace="media", pod=~"booklore.*"} |~ "(?i)migrat|flyway|error|fail"`).
- Biblioteca, usuarios y progreso intactos en la UI tras la migración de esquema.
- Login OIDC vía Authelia sigue funcionando.
- Dejar constancia en las notas de que `DISK_TYPE=NETWORK` no aplica (volumen hostPath local) y enlazar la guía #120.

### Rollback

Si una fase falla:
- Revertir `lib/versions.json` a la versión anterior (`booklore/booklore:v2.2.1` para volver al origen, o `grimmory/grimmory:v2.2.4` si falla solo la Fase 3) y `/deploy`.
- Si el esquema quedó migrado y hay que volver atrás de verdad: restaurar la DB desde `/tmp/booklore-backup.sql` y el volumen desde `/cold-data/booklore-migration-backup.tar.gz`.
<!-- SECTION:PLAN:END -->
