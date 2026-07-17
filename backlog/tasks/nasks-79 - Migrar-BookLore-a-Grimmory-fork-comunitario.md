---
id: NASKS-79
title: Migrar BookLore a Grimmory (fork comunitario)
status: In Progress
assignee: []
created_date: '2026-07-10 20:43'
updated_date: '2026-07-17 16:39'
labels:
  - media
  - migration
dependencies: []
references:
  - 'https://github.com/grimmory-tools/grimmory'
  - 'https://github.com/orgs/grimmory-tools/discussions/120'
  - 'https://github.com/grimmory-tools/grimmory/blob/develop/README.md'
priority: medium
ordinal: 1000
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
- En vez de un backup pasivo, se **duplica** el estado: BBDD `grimmory` (copia de `booklore`) + directorio `/cold-data/grimmory` (copia de `/cold-data/booklore`). Grimmory corre sobre la copia y los originales de booklore quedan congelados como rollback vivo. El módulo se renombra por completo a `grimmory` (dominio `books.danielramos.me` se mantiene).
- Avisos de la comunidad (no aplican / a verificar): `DISK_TYPE=NETWORK` deshabilita operaciones de fichero en mounts NFS/SMB → no aplica, el volumen es hostPath local. Kobo Sync tenía incidencias con `kepubify` en setups no docker-compose → verificar si se usa.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lib/versions.json tiene una entrada `grimmory` apuntando a `grimmory/grimmory` con un tag de versión estable pinneado (no latest); la entrada `booklore` se elimina
- [ ] #2 MariaDB provisiona una BBDD `grimmory` + usuario `grimmory` (vía el helper createUser); la BBDD original `booklore` se conserva intacta como rollback
- [ ] #3 Los datos se copian: la BBDD `booklore` se duplica en `grimmory` y el directorio hostPath /cold-data/booklore se copia a /cold-data/grimmory (originales conservados para rollback)
- [ ] #4 El módulo se renombra por completo a grimmory: dir lib/media/grimmory, nombre de deployment/container/service, ConfigMap/Secret, entrada de versions.json y label `app` (nueva Application en ArgoCD); el env DATABASE_* apunta a la BBDD/usuario `grimmory` y se eliminan BOOKLORE_PORT y las vars SPRINGDOC_*
- [ ] #5 El cliente OIDC en Authelia se renombra a `grimmory` (client_id, client_name, claims_policy) manteniendo el dominio books.danielramos.me, y el login SSO sigue funcionando
- [ ] #6 Tras el deploy el pod arranca sano (startup probe /api/v1/healthcheck en 6060 OK) y la biblioteca existente (libros, usuarios, progreso) se ve intacta en la UI, confirmando la migración de esquema v2→v3 sobre la BBDD `grimmory`
- [ ] #7 `grep -ri booklore` sobre el código/config activo del repo (excluyendo dist/, vendor/ y backlog/) no devuelve resultados, con la única excepción del package Java `org.booklore` en el logger de logback (es el package real del binario de Grimmory, obligatorio para capturar sus logs)
- [ ] #8 Se deja constancia de que DISK_TYPE por defecto es LOCAL (volumen hostPath local; NETWORK no aplica) y de la referencia a la guía oficial de transición (#120)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Migración con **rename limpio y completo** a `grimmory`, usando duplicación en vez de backup pasivo: se crea una BBDD `grimmory` (copia de `booklore`) y un directorio hostPath `/cold-data/grimmory` (copia de `/cold-data/booklore`), de modo que **los originales de booklore quedan congelados como rollback vivo**. El módulo entero pasa a llamarse `grimmory`; el dominio `books.danielramos.me` se mantiene (es genérico y no rompe bookmarks ni el redirect OIDC).

Contexto de versiones: BookLore actual = `booklore/booklore:v2.2.1`. Grimmory última estable = `v3.2.4` (2026-07-01). La discusión oficial #120 valida `grimmory/grimmory:v2.2.4` como drop-in directo desde BookLore v2.2.x. Puerto interno (6060) y healthcheck (`/api/v1/healthcheck`) idénticos.

**Secuencia clave:** el `DATABASE_*` apunta a la BBDD `grimmory` ya en la Fase 3 — no puede diferirse, porque las migraciones de esquema v2→v3 de la Fase 4 deben correr sobre la copia `grimmory`, dejando la BBDD `booklore` intacta como rollback. Por eso el rename del módulo se hace junto con el swap de imagen en la Fase 3 (un solo deploy), no en un paso posterior.

### Fase 0 — Verificación previa (sin cambios) ✅

Objetivo: confirmar imagen/tags y env vars antes de tocar nada.

1. Imagen/tags (verificado con skopeo): `grimmory/grimmory` (Docker Hub) sirve `v2.2.4` y `v3.2.4`.
   ```bash
   skopeo list-tags docker://docker.io/grimmory/grimmory | jq -r '.Tags[]' | grep -E '^v(2\.2\.4|3\.2\.4)$'
   ```
   Imagen canónica: `grimmory/grimmory` (Docker Hub, mismo estilo bare-name que la actual `booklore/booklore`). Las `references` del ticket citan `ghcr.io/grimmory-tools/grimmory` como alternativa equivalente; usamos Docker Hub y `versions.json`/AC #1 quedan consistentes con esa elección.
2. Env vars (verificado contra el README de Grimmory):
   - Se mantienen: `DATABASE_URL`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `USER_ID`, `GROUP_ID`, `TZ`, `LOGGING_CONFIG`.
   - **Eliminar**: `BOOKLORE_PORT` (ya no se usa; puerto interno 6060 fijo) y `SPRINGDOC_API_DOCS_ENABLED`/`SPRINGDOC_SWAGGER_UI_ENABLED` (Grimmory usa `API_DOCS_ENABLED`, default `false` → basta con omitirlas).
   - `DISK_TYPE` default `LOCAL` (hostPath local) → se omite; `NETWORK` no aplica.
3. **Package Java del logger** (verificado en `grimmory-tools/grimmory` rama develop): Grimmory renombró el package a **`org.booklore`** (el original era `com.adityachandel.booklore`). Consecuencias:
   - El `<logger name=...>` de `booklore.logback-spring.xml` (hoy `com.adityachandel.booklore`) debe pasar a `org.booklore` en la Fase 3, o el logger de app no capturará los logs de Grimmory (caerían al root).
   - `org.booklore` sigue conteniendo la cadena `booklore` → el AC #7 (`grep -ri booklore` sin resultados) se relaja para admitir **esa única referencia obligatoria** (es el package real del binario).

**Checkpoint Fase 0:** ambos tags aparecen en skopeo; env vars a eliminar identificadas; package logger de Grimmory confirmado (`org.booklore`).

### Fase 1 — Provisionar BBDD `grimmory` + usuario `grimmory` (deploy databases)

Objetivo: crear la BBDD y el usuario destino con el helper existente. Reutiliza el patrón de `userBooklore` en `lib/databases/mariadb/mariadb.libsonnet`.

1. Generar una contraseña nueva **a un fichero temporal** (nunca al contexto) y cifrarla cluster-wide en los dos sitios que deben compartir el mismo plaintext, luego borrar el fichero:
   ```bash
   openssl rand -base64 32 > /tmp/grimmory-db-pass.txt
   # → mariadb.secrets.json (userGrimmory) y grimmory.secrets.json (shared.DATABASE_PASSWORD)
   cat /tmp/grimmory-db-pass.txt | ./scripts/encrypt-secret.sh --cluster-wide   # (x2, una por destino)
   rm -f /tmp/grimmory-db-pass.txt
   ```
2. En `mariadb.libsonnet`, añadir junto a `userBooklore`:
   ```jsonnet
   userGrimmory: self.createUser('grimmory', secrets.userGrimmory, self.createUserMigration, self.sealedSecret),
   ```
3. **Desplegar** (`/deploy`, entorno databases). El Job `mariadb-create-user-grimmory` crea la BBDD `grimmory` (vacía) + usuario `grimmory`.

**Checkpoint Fase 1:** el Job `mariadb-create-user-grimmory` completa OK; la BBDD `grimmory` existe (`SHOW DATABASES` dentro del pod). La BBDD `booklore` sigue intacta.

### Fase 2 — Copiar datos booklore → grimmory (sin deploy)

Objetivo: poblar la copia. Los originales de booklore quedan como rollback.

1. **Pre-check** (sin exponer el valor): confirmar que el pod expone `MYSQL_ROOT_PASSWORD` y que existe `mariadb-dump`:
   ```bash
   kubectl exec -n databases mariadb-0 -- printenv | grep -o '^MYSQL_ROOT_PASSWORD='   # imprime solo la clave
   kubectl exec -n databases mariadb-0 -- command -v mariadb-dump
   ```
   Si el nombre del env difiere, ajústalo en el paso siguiente (a diferencia del `create-user.sh`, aquí no hay `set -e`, así que un nombre mal resolvería a vacío y el dump fallaría con error de auth).
2. **BBDD** — copia en un solo pipe dentro del pod (root pass resuelta dentro, nunca en contexto):
   ```bash
   kubectl exec -n databases mariadb-0 -- bash -c \
     'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction booklore \
      | mariadb -u root -p"$MYSQL_ROOT_PASSWORD" grimmory'
   ```
3. **Volumen hostPath** — copiar el árbol conservando el original (nota: `books/` puede ser grande; verificar espacio libre con `df` antes):
   ```bash
   ssh nas 'sudo cp -a /cold-data/booklore /cold-data/grimmory'
   ```

**Checkpoint Fase 2:**
- El nº de tablas en `grimmory` coincide con `booklore` (`SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='grimmory'` vs `booklore`).
- `ssh nas 'sudo du -sh /cold-data/grimmory'` con tamaño similar al original.

### Fase 3 — Rename del módulo a Grimmory + swap a v2.2.4 (apuntando a BBDD grimmory)

Objetivo: reemplazo drop-in del fork sobre la copia de datos, con el rename completo del módulo en un solo deploy.

1. **Renombrar el módulo** `lib/media/booklore/` → `lib/media/grimmory/`:
   - `booklore.libsonnet` → `grimmory.libsonnet`, `booklore.secrets.json` → `grimmory.secrets.json`, `booklore.logback-spring.xml` → `grimmory.logback-spring.xml`.
   - Deployment/container/service: `grimmory`. Volúmenes hostPath → `/cold-data/grimmory/{data,books,bookdrop}`.
   - `configEnv`: `DATABASE_URL: jdbc:mariadb://mariadb.databases.svc.cluster.local:3306/grimmory`, `DATABASE_USERNAME: grimmory`; **eliminar** `BOOKLORE_PORT`, `SPRINGDOC_*`. Se mantiene `LOGGING_CONFIG: /config/logback-spring.xml` (la ruta montada la fija `configMap.forFile('logback-spring.xml', ...)`, no el nombre del `.xml` renombrado).
   - **logback** (`grimmory.logback-spring.xml`): cambiar el `<logger name="com.adityachandel.booklore" ...>` → `name="org.booklore"` y el comentario `Booklore application logger` → `Grimmory application logger` (package real de Grimmory, ver Fase 0).
   - `sealedSecret`: `grimmory-shared-sealed-secret` (de `grimmory.secrets.json`, estructura `{ "shared": { "DATABASE_PASSWORD": ... } }` que consume `secrets.shared`).
   - `ingressRoute`: se mantiene `books.danielramos.me`.
2. **versions.json**: eliminar la entrada `booklore`, añadir:
   ```json
   "grimmory": { "image": "grimmory/grimmory", "version": "v2.2.4" },
   ```
3. **environments/media/main.jsonnet**: renombrar el import y la key `booklore:` → `grimmory:` (esto cambia el label `app` → nueva Application `grimmory` en ArgoCD; la vieja `booklore` se prunea sola, arrastrando su Deployment/Service en la misma sync).
4. **Authelia** (entorno `auth`, namespace `auth`) — el OIDC de booklore NO se configura por env en el módulo: el `client_id` vive dentro de la BBDD (que copiamos en la Fase 2), así que **hay que preservar el VALOR del client_id** para no romper el login; solo se renombran nombres/claves.
   En `lib/auth/authelia/authelia.config.yml`:
   - Renombrar el bloque de `claims_policies` `booklore:` → `grimmory:` **y** la referencia `claims_policy: booklore` → `grimmory` en el cliente.
   - `client_name: Booklore` → `Grimmory`.
   - La env ref del client_id `{{ env `IDENTITY_PROVIDERS_OIDC_CLIENTS_BOOKLORE_CLIENT_ID` }}` → `..._GRIMMORY_CLIENT_ID`.
   - `redirect_uris` se mantiene (`https://books.danielramos.me/oauth2-callback`).
   Re-cifrar el **mismo valor** bajo la nueva clave en `authelia.secrets.json` (ámbito **strict**, no cluster-wide) y eliminar la clave vieja, sin exponer el plaintext (confirmar antes el nombre real del Secret descifrado):
   ```bash
   kubectl get secret authelia-sealed-secret -n auth \
     -o jsonpath='{.data.IDENTITY_PROVIDERS_OIDC_CLIENTS_BOOKLORE_CLIENT_ID}' | base64 -d > /tmp/grimmory-cid.txt
   cat /tmp/grimmory-cid.txt | ./scripts/encrypt-secret.sh auth authelia-sealed-secret
   # → pegar la salida bajo la nueva clave IDENTITY_PROVIDERS_OIDC_CLIENTS_GRIMMORY_CLIENT_ID en authelia.secrets.json (.authelia)
   rm -f /tmp/grimmory-cid.txt
   ```
   Luego borrar del JSON la entrada `IDENTITY_PROVIDERS_OIDC_CLIENTS_BOOKLORE_CLIENT_ID`. Nota: **no** generar un client_id nuevo — el valor debe conservarse porque el `client_id` que envía Grimmory está guardado en la BBDD copiada; cambiarlo rompería la coherencia BBDD↔Authelia y el login.
5. Compilar y verificar **ambos entornos** (media y auth):
   ```bash
   tk eval environments/media | jq '.grimmory.deployment.spec.template.spec.containers[0].image'   # "grimmory/grimmory:v2.2.4"
   tk eval environments/media | jq '.grimmory.deployment.spec.template.spec.containers[0].env'      # DATABASE_URL → /grimmory, sin BOOKLORE_PORT/SPRINGDOC_*
   tk eval environments/auth  >/dev/null                    # compila sin error tras el rename del cliente OIDC (sale ≠0 si hay error de Jsonnet)
   tk eval environments/auth  | grep -c 'client_name: Grimmory'   # ≥1: el rename llegó al config renderizado
   tk eval environments/auth  | grep -ci booklore           # 0: no queda ninguna referencia a booklore en el config
   ```
6. **Desplegar** (`/deploy`). El cambio toca **dos entornos** (`media` + `auth`): ambos entran en el mismo push → CI exporta → ArgoCD sincroniza las dos Applications. Authelia recarga su config vía Reloader al cambiar su ConfigMap/Secret. Verifica que Authelia haya recargado (logs) **antes** del paseo Playwright, o el primer login OIDC podría pillar la config vieja.

**Checkpoint Fase 3:**
- Pod `grimmory` en `media` `Running`/`Ready` con imagen `grimmory/grimmory:v2.2.4` (`kubectl get pod -n media -l app=grimmory ...`).
- El Deployment/Service `booklore` ya NO existe en `media` (pruneado por ArgoCD al desaparecer su Application): `kubectl get deploy -n media booklore` → NotFound.
- Authelia recargó la config (Loki: `{namespace="auth", pod=~"authelia.*"} |~ "(?i)reload|config"`), sin errores de cliente OIDC.
- Sin CrashLoop. Arranque vía Loki: `{namespace="media", pod=~"grimmory.*"} |~ "(?i)started|error|fail"`.
- **Paseo funcional (Playwright)** — vía el MCP de Playwright, conducir el navegador de punta a punta:
  1. Navegar a `https://books.danielramos.me` y completar el login OIDC vía Authelia (redirect → autenticación/2FA → callback). Confirma el cliente `grimmory`.
  2. La biblioteca carga con los libros existentes (portadas, títulos, conteo coherente con lo previo).
  3. Abrir un libro y confirmar que el lector (reader) abre y renderiza el contenido.
  4. El progreso de lectura de un libro ya empezado se conserva.
  5. Sin errores en consola (`browser_console_messages`) ni peticiones fallidas relevantes (`browser_network_requests`).

### Fase 4 — Bump a la última estable (v3.2.4)

Objetivo: versión mantenida al día; aquí corren las migraciones de esquema v2→v3 sobre la BBDD `grimmory` (la `booklore` original queda como rollback).

1. `versions.json`, entrada `grimmory`: subir a `"version": "v3.2.4"`.
2. Verificar el tag:
   ```bash
   tk eval environments/media | jq '.grimmory.deployment.spec.template.spec.containers[0].image'   # "grimmory/grimmory:v3.2.4"
   ```
3. **Desplegar** (`/deploy`).

> Nota: el customManager de Renovate trackea las imágenes de `versions.json`; puede abrir el PR de bump a `v3.2.4` por su cuenta. Si aparece antes, sirve igual — mismo destino; verifica el checkpoint antes de mergear.

**Checkpoint Fase 4:**
- Pod `grimmory` `Running`/`Ready` con imagen `grimmory/grimmory:v3.2.4`.
- Loki muestra las migraciones de esquema aplicadas sin error: `{namespace="media", pod=~"grimmory.*"} |~ "(?i)migrat|flyway|error|fail"`.
- **Paseo funcional (Playwright)** — repetir el paseo de la Fase 3 (login OIDC → biblioteca → abrir libro → progreso → consola/red limpias), prestando atención a que la migración de esquema v2→v3 no haya roto la biblioteca ni el progreso.

### Fase 5 — Limpieza del repo y verificación de rename

Objetivo: dejar el repo limpio de `booklore`. NO se borra todavía el estado runtime viejo (BBDD + directorio) — eso queda como rollback vivo hasta la Fase 6.

1. `grep -ri booklore --exclude-dir={dist,vendor,backlog,.git}` sobre el repo → único resultado admisible: `org.booklore` en `grimmory.logback-spring.xml` (ver AC #7). Se excluye `backlog/` entero porque el propio ticket y el histórico contienen "booklore". Incluye retirar `userBooklore` de `mariadb.libsonnet` y `mariadb.secrets.json`, y confirmar que ya no queda la clave `..._BOOKLORE_CLIENT_ID` en `authelia.secrets.json`.
2. Verificar que ArgoCD ya no tiene la Application `booklore` (se pruneó al cambiar el label en la Fase 3).
3. Dejar constancia en Implementation Notes: `DISK_TYPE` default `LOCAL` (NETWORK no aplica) + enlace a la guía #120.

### Fase 6 — Borrar el estado viejo copiado (tras periodo de gracia)

Objetivo: una vez confirmada la estabilidad de Grimmory sobre la copia, eliminar el estado runtime de booklore que servía de rollback vivo. Este es el punto de no retorno para el rollback por duplicación.

1. **BBDD** — drop de la base y el usuario `booklore` en MariaDB (root pass resuelta dentro del pod, nunca en contexto):
   ```bash
   kubectl exec -n databases mariadb-0 -- bash -c \
     'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`booklore\`; DROP USER IF EXISTS '"'"'booklore'"'"'@'"'"'%'"'"';"'
   ```
2. **Directorio de datos** — borrar el árbol copiado original en el NAS:
   ```bash
   ssh nas 'sudo rm -rf /cold-data/booklore'
   ```

**Checkpoint Fase 6:**
- `SHOW DATABASES` en MariaDB no lista `booklore`; `ssh nas 'ls /cold-data/booklore'` da "No such file or directory".
- **Paseo funcional (Playwright)** — repetir el paseo de la Fase 3 para confirmar que, tras borrar la BBDD y el directorio viejos, Grimmory sigue funcionando sobre su propia copia (biblioteca, lector y progreso intactos). Esto descarta cualquier dependencia residual del estado eliminado.

### Rollback

Si una fase falla **antes de la Fase 6**, como los originales de booklore están intactos:
- **Fase 3/4 fallan**: revertir el módulo y `versions.json` al estado `booklore/booklore:v2.2.1` (`git revert`/checkout del commit) y `/deploy`. La BBDD `booklore` y `/cold-data/booklore` siguen ahí sin tocar → el servicio vuelve exactamente al estado previo.
- No hace falta restaurar desde dump: la duplicación **es** el mecanismo de rollback.
- Tras la Fase 6 ya no hay rollback por duplicación: solo se ejecuta cuando Grimmory lleva tiempo estable.
<!-- SECTION:PLAN:END -->
