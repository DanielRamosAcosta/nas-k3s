---
id: NASKS-71
title: Desplegar CouchDB para Obsidian LiveSync
status: Done
assignee: []
created_date: '2026-06-25 22:44'
updated_date: '2026-06-26 18:34'
labels: []
dependencies: []
references:
  - 'https://github.com/vrtmrz/obsidian-livesync'
  - >-
    https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/setup_own_server.md
  - lib/databases/mariadb
priority: medium
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Desplegar una instancia de CouchDB en el clúster como backend de sincronización para el plugin Obsidian LiveSync, expuesta vía `couchdb.danielramos.me` (orange-proxied por Cloudflare), con un usuario dedicado no-admin y aprovisionamiento declarativo de la database.

## 🎯 Contexto funcional

Se quiere sincronizar una vault de Obsidian entre varios dispositivos (incluyendo móvil y desde fuera de casa) usando el plugin **Self-hosted LiveSync**, que requiere un CouchDB accesible por HTTPS. El plugin se autentica con **basic auth nativo de CouchDB** (usuario/contraseña), NO con OIDC/forward-auth, por lo que el ingress no puede ir detrás de Authelia.

La instancia se nombra por lo que es (`couchdb`) y no por su consumidor, para poder **reutilizarla en el futuro** para otras apps: CouchDB es multi-database, así que cada app futura tendría su propia database + usuario aislado bajo la misma instancia.

## ⚙️ Contexto técnico

Diseño cerrado en el interrogatorio `/grill-me`:

| Aspecto | Decisión |
|---|---|
| **Exposición** | Externa, HTTPS, **orange-proxied** por Cloudflare (WAF/rate-limit/geoblock en el borde). NO necesita rate-limit ni Crowdsec propios — eso solo lo lleva Immich por ser gray-cloud / DNS-only por el límite de 100 MB de upload de CF. |
| **Auth ingress** | `u.ingressRoute.from(service, 'couchdb.danielramos.me')` directo, **sin Authelia, sin middlewares propios**. Usa `cloudflare-origin-cert` por defecto (camino orange). Seguridad: WAF/rate-limit de Cloudflare + basic auth de CouchDB con `require_valid_user` + password fuerte. |
| **Dominio** | `couchdb.danielramos.me` (reutilizable). |
| **Modelo de usuarios** | Admin (bootstrap + administración) + usuario dedicado **no-admin** `obsidian` con acceso solo a su DB (mínimo privilegio, como en Postgres/MariaDB). |
| **Aprovisionamiento** | Job de migración declarativo (estilo `mariadb.create-user.sh`), idempotente: crea DB `obsidian-vault`, usuario `obsidian` en `_users`, y `_security` de la DB. |
| **Config** | `local.ini` mínimo (regla minimize-config del CLAUDE.md): `require_valid_user = true`, CORS con origins `app://obsidian.md,capacitor://localhost,http://localhost`, límites de tamaño. Admin vía env (`COUCHDB_USER`/`COUCHDB_PASSWORD`) desde SealedSecret. Valores exactos verificados contra la doc oficial de LiveSync al implementar (son quisquillosos y dependen de versión). |
| **Límite tamaño** | `max_http_request_size`/`max_document_size` ≈ 100 MB (coincide con el techo del proxy de Cloudflare; LiveSync trocea en chunks pequeños, así que solo un adjunto individual >100 MB fallaría — no rompe el resto de la sync). |
| **Storage** | hostPath `/data/couchdb` (SSD, estado de app), igual que MariaDB/Postgres. |
| **Imagen** | `apache/couchdb` 3.x estable, tag fijado en `versions.json` (no `latest`; verificar tag exacto contra el registry al implementar). |
| **Ubicación** | Módulo nuevo `lib/databases/couchdb/couchdb.libsonnet`, añadido a `environments/databases/main.jsonnet` con `couchdb.new()` + `u.labelApp()` (ArgoCD lo recoge solo). |
| **Secrets** | Scope **strict** (namespace `databases`) — el único consumidor en el clúster es el Job de migración; la contraseña del usuario `obsidian` se introduce a mano en el plugin de Obsidian. |
| **Backups** | Ninguno ahora (las réplicas de los dispositivos LiveSync sirven de recuperación). Se crea una tarea aparte. |

### Gotchas de implementación detectados

1. **DNS**: crear el registro `couchdb.danielramos.me` en Cloudflare **proxied (orange)** — paso manual, no versionado en el repo.
2. **Probe**: con `require_valid_user=true`, un probe HTTP a `/_up` daría 401 → usar **probe TCP** al puerto 5984 (como MariaDB).
3. **Persistencia de config**: fijar `COUCHDB_SECRET` (env desde SealedSecret) para que las sesiones/cookies persistan entre reinicios, ya que el `local.ini` runtime no se persiste.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
El plan se divide en fases pequeñas con despliegue intermedio (commit + push → ArgoCD sync) y un checkpoint de verificación al final de cada una, para iterar con feedback rápido.

> **Config verificada contra la doc oficial de LiveSync (Context7 `/vrtmrz/obsidian-livesync`).** Settings exactos que el plugin exige en el servidor CouchDB: `chttpd/require_valid_user=true`, `chttpd_auth/require_valid_user=true`, `httpd/WWW-Authenticate=Basic realm="couchdb"`, `enable_cors=true` (en `httpd` y `chttpd`), `cors/credentials=true`, `cors/origins=app://obsidian.md,capacitor://localhost,http://localhost`, `max_http_request_size` y `max_document_size`. El volumen de config del contenedor oficial es `/opt/couchdb/data` (datos) y `/opt/couchdb/etc/local.d` (config).

---

### Fase 0 — Scaffolding + versiones + secretos (sin desplegar todavía)

**Objetivo:** dejar el módulo creado, las imágenes fijadas y los secretos cifrados, sin lógica funcional aún.

1. Crear el directorio del módulo:
   ```bash
   mkdir -p lib/databases/couchdb
   ```
2. Añadir las imágenes a `lib/versions.json` (verificar el tag estable 3.x exacto contra Docker Hub al implementar; no usar `latest`):
   ```json
   "couchdb": { "image": "docker.io/apache/couchdb", "version": "3.5.0" },
   "curl":    { "image": "docker.io/curlimages/curl", "version": "8.11.1" }
   ```
3. **Secretos (scope strict, namespace `databases`).** Nombres derivados por la API de utils:
   - `couchdb-sealed-secret` → claves `COUCHDB_USER`, `COUCHDB_PASSWORD`, `COUCHDB_SECRET`.
   - `couchdb-create-user-obsidian-sealed-secret` → clave `USER_PASSWORD` (password del usuario `obsidian`).

   Seguir la regla de seguridad del CLAUDE.md (nunca imprimir plaintext; generar a archivo, cifrar, borrar). El `COUCHDB_USER`/`COUCHDB_PASSWORD`/`COUCHDB_SECRET` son internos (solo los usan el contenedor y el job) → se generan aleatorios. El `USER_PASSWORD` de `obsidian` **lo elige el usuario** (debe conocerlo para meterlo en el plugin) → lo escribe él en un fichero:
   ```bash
   # Admin: usuario fijo 'admin', password aleatoria
   printf 'admin' | ./scripts/encrypt-secret.sh databases couchdb-sealed-secret              # COUCHDB_USER
   openssl rand -base64 32 | tr -d '\n' > /tmp/couch-admin.txt
   cat /tmp/couch-admin.txt | ./scripts/encrypt-secret.sh databases couchdb-sealed-secret    # COUCHDB_PASSWORD
   # Secret para firmar cookies de sesión (persistencia entre reinicios)
   openssl rand -hex 32 | tr -d '\n' > /tmp/couch-secret.txt
   cat /tmp/couch-secret.txt | ./scripts/encrypt-secret.sh databases couchdb-sealed-secret   # COUCHDB_SECRET
   # Password del usuario obsidian (el USUARIO lo escribe en el fichero — él lo teclea luego en el plugin)
   cat /tmp/couch-obsidian.txt | ./scripts/encrypt-secret.sh databases couchdb-create-user-obsidian-sealed-secret  # USER_PASSWORD
   rm -f /tmp/couch-admin.txt /tmp/couch-secret.txt /tmp/couch-obsidian.txt
   ```
   La salida cifrada (segura) de cada comando se pega en `lib/databases/couchdb/couchdb.secrets.json`. **Ojo con la forma:** el admin es un objeto con sus claves, pero `userObsidian` es un **string sellado plano** (no un objeto), porque el helper `createUser` lo envuelve luego como `{ USER_PASSWORD: <string> }` — exactamente el patrón de `userImmich` en `postgres.secrets.json`:
   ```json
   {
     "couchdb":      { "COUCHDB_USER": "<sealed>", "COUCHDB_PASSWORD": "<sealed>", "COUCHDB_SECRET": "<sealed>" },
     "userObsidian": "<sealed>"
   }
   ```
   **Este fichero SÍ se commitea** (los valores son sellados → seguros; en este repo los 23 `*.secrets.json` están versionados y CI los necesita para `tk eval`). El CLAUDE.md dice que están "en gitignore" pero la realidad del repo es lo contrario — NO lo ignores.

**Sin despliegue en esta fase** (aún no hay recursos referenciados desde el entorno).

---

### Fase 1 — CouchDB core: StatefulSet + Service + config + SealedSecret (1er despliegue)

**Objetivo:** CouchDB arranca, el admin funciona y las system DBs existen. Sin ingress ni migración todavía.

1. Crear `lib/databases/couchdb/couchdb.config.ini` (solo deltas que LiveSync exige + `single_node` para que se auto-creen `_users`/`_replicator`/`_global_changes`):
   ```ini
   [couchdb]
   single_node = true
   max_document_size = 50000000

   [chttpd]
   require_valid_user = true
   enable_cors = true
   max_http_request_size = 104857600

   [chttpd_auth]
   require_valid_user = true

   [httpd]
   enable_cors = true
   WWW-Authenticate = Basic realm="couchdb"

   [cors]
   credentials = true
   origins = app://obsidian.md,capacitor://localhost,http://localhost
   headers = accept, authorization, content-type, origin, referer
   methods = GET, PUT, POST, HEAD, DELETE
   max_age = 3600
   ```
   > **Nota sobre límites:** LiveSync recomienda `max_http_request_size=4294967296` (4 GB). Aquí se fija a ~100 MB para alinear con el techo de Cloudflare (orange). El límite real lo impone CF en el borde; revisar con el usuario si se prefiere subir el valor del origen por encima de 100 MB para que CF sea siempre el único cuello de botella. **(Punto a confirmar — ver dudas al final.)**

2. Crear `lib/databases/couchdb/couchdb.libsonnet` siguiendo el patrón de `mariadb.libsonnet`/`postgres.libsonnet`:
   - `local secrets = import 'databases/couchdb/couchdb.secrets.json';`
   - `statefulSet('couchdb', replicas=1)`, contenedor `couchdb` con `u.image(versions.couchdb.image, versions.couchdb.version)`.
   - Puerto `containerPort.new('couchdb', 5984)`.
   - Env: `u.envVars.fromSealedSecret(self.sealedSecret)` (inyecta `COUCHDB_USER`/`COUCHDB_PASSWORD`/`COUCHDB_SECRET`).
   - Volúmenes (`withVolumes([...])`) — **declarar AMBOS**, si no el `volumeMount` referenciaría un volumen inexistente y el pod no arrancaría:
     - `volume.fromHostPath('data', '/data/couchdb')`.
     - `u.volume.fromConfigMap(self.config)` (el volumen del ConfigMap del `.ini`, nombre `couchdb-config-ini`).
   - Volume mounts:
     - `volumeMount.new('data', '/opt/couchdb/data')`.
     - ConfigMap del `.ini` montado como **archivo** vía `u.volumeMount.fromFile(self.config, '/opt/couchdb/etc/local.d')` (subPath → monta en `/opt/couchdb/etc/local.d/couchdb.config.ini`, coexiste con el `docker.ini` que genera la imagen; no shadowea el directorio).
   - **Init container `fix-perms`** (imagen busybox, `runAsUser: 0`) que hace `chown -R 5984:5984 /opt/couchdb/data` — la imagen oficial corre como uid 5984 y el hostPath se crea como root. (Si en el deploy se ve que no hace falta, se elimina.)
   - Probe: `u.probes.stateful.tcp(5984)` (TCP, no HTTP — con `require_valid_user=true` un GET a `/_up` da 401).
   - `service: k.util.serviceFor(self.statefulSet)`.
   - `sealedSecret: u.sealedSecret.forEnv(self.statefulSet, secrets.couchdb)` (**strict**, no `.wide`).
   - `config: u.configMap.forFile('couchdb.config.ini', importstr './couchdb.config.ini')`.
3. Conectar el módulo en `environments/databases/main.jsonnet`:
   ```jsonnet
   local couchdb = import 'databases/couchdb/couchdb.libsonnet';
   ...
   u.Environment({
     postgres: postgres.new(),
     valkey: valkey.new(),
     mariadb: mariadb.new(),
     couchdb: couchdb.new(),
   })
   ```
4. Validar localmente:
   ```bash
   tk eval environments/databases | jq '.couchdb | keys'
   ```
5. **Desplegar:** commit + push a `main` → CI exporta a rama `manifests` → `argocd app sync couchdb --grpc-web` (la Application se genera sola vía `u.labelApp()`).
6. **Checkpoint de verificación (Fase 1):**
   - Pod `couchdb-0` en `Running` (logs vía Loki: `{namespace="databases", pod=~"couchdb.*"}`).
   - Desde dentro del clúster (`kubectl exec` a otro pod o `kubectl run` efímero con curl): `GET http://couchdb.databases.svc.cluster.local:5984/_up` con `--user admin:...` → 200.
   - `GET /_all_dbs` con auth → incluye `_users`, `_replicator`, `_global_changes` (confirma que `single_node` los creó).
   - Sin auth → 401 (confirma `require_valid_user`).

---

### Fase 2 — Job de migración: database + usuario + `_security` (2º despliegue)

**Objetivo:** existe la DB `obsidian-vault`, el usuario no-admin `obsidian`, y el acceso está restringido a esa DB.

1. Crear `lib/databases/couchdb/couchdb.create-user.sh` (idempotente, vía API HTTP con curl). **Escribirlo en POSIX `sh`, NO bash** (la imagen `curlimages/curl` es alpine/ash y no trae bash; se invoca con `/bin/sh`). Evitar bashisms (`[[ ]]`, arrays); `set -eu` y `pipefail` van bien en ash.
   - Valida env: `COUCHDB_USER`, `COUCHDB_PASSWORD`, `USER_NAME`, `USER_PASSWORD`, `DB_NAME`.
   - Host por defecto `http://couchdb.databases.svc.cluster.local:5984`.
   - Espera a `/_up` **autenticado** (`--user "$COUCHDB_USER:$COUCHDB_PASSWORD"`) — con `require_valid_user=true`, `/_up` sin auth da 401 y el loop nunca vería 200.
   - `PUT /$DB_NAME` (crear DB; tolerar 412 si ya existe).
   - `PUT /_users/org.couchdb.user:$USER_NAME` con body `{"name","password","roles":[],"type":"user"}` (tolerar 409 si ya existe).
   - `PUT /$DB_NAME/_security` (idempotente, sobrescribe). Poner a `obsidian` como **member** (`members.names=["obsidian"]`). **Nota LiveSync:** un member puede leer/escribir docs normales pero NO design docs; si en Fase 4 "Check database configuration" falla con 403 al crear índices/design docs, añadir `obsidian` también a `admins.names` (admin local de SU base — sigue aislado de las demás DBs).
   - **Idempotencia con curl:** distinguir "ya existe" (412/409, tolerable) de fallo real (5xx). No usar un `|| true` ciego sobre `curl -f`; comprobar el código HTTP (`-o /dev/null -w '%{http_code}'`) y fallar solo ante 5xx/errores de red.
2. En `couchdb.libsonnet` añadir (patrón `createUser` de postgres/mariadb):
   - `createUserMigration: u.configMap.forFile('couchdb.create-user.sh', importstr './couchdb.create-user.sh')`.
   - `userObsidian: self.createUser('obsidian', 'obsidian-vault', secrets.userObsidian, self.createUserMigration, self.sealedSecret)`.
   - Helper `createUser(name, dbName, password, configMap, secret)` → `Job` `couchdb-create-user-<name>`:
     - Imagen `u.image(versions.curl.image, versions.curl.version)`, command `['/bin/sh','/mnt/scripts/couchdb.create-user.sh']`.
     - Env: `USER_NAME`, `DB_NAME` (plain) + `u.envVars.fromSealedSecret(self.userSecret)` (USER_PASSWORD) + `u.envVars.fromSealedSecret(secret)` (admin).
     - `userSecret: u.sealedSecret.forEnv(self.migrationJob, { USER_PASSWORD: password })` (**strict**).
     - `restartPolicy: OnFailure`, monta el script con `u.volumeMount.fromFile(configMap, '/mnt/scripts')` + `u.volume.fromConfigMap(configMap)`.
3. `tk eval environments/databases | jq '.couchdb | keys'` para validar.
4. **Desplegar** (commit + push + `argocd app sync couchdb`).
5. **Checkpoint (Fase 2):**
   - Job `couchdb-create-user-obsidian` completado (logs en Loki).
   - `GET /_all_dbs` con admin → incluye `obsidian-vault`.
   - `GET /obsidian-vault` con `--user obsidian:<pass>` → 200; `GET /_users` con `obsidian` → 403 (aislamiento correcto).
   - Re-lanzar el job (borrar el Job y resync) → vuelve a completar sin error (idempotencia).

---

### Fase 3 — IngressRoute + DNS (3er despliegue)

**Objetivo:** CouchDB accesible por HTTPS en `couchdb.danielramos.me`, orange-proxied, con CORS correcto para Obsidian.

1. En `couchdb.libsonnet` añadir:
   ```jsonnet
   ingress_route: u.ingressRoute.from(self.service, 'couchdb.danielramos.me'),
   ```
   (usa `tls.store: default` = `cloudflare-origin-cert`, el camino orange estándar; sin middlewares, sin Authelia).
2. **Paso manual (no versionado):** crear el registro DNS `couchdb.danielramos.me` en Cloudflare como **proxied (orange)**, apuntando al mismo destino que el resto de servicios orange. Documentarlo aquí.
3. **Desplegar** (commit + push + `argocd app sync couchdb`).
4. **Checkpoint (Fase 3):**
   - `curl -I https://couchdb.danielramos.me/` → responde (401 sin auth es correcto), TLS válido vía Cloudflare.
   - `curl --user obsidian:<pass> https://couchdb.danielramos.me/obsidian-vault` → 200.
   - Preflight CORS: `curl -X OPTIONS https://couchdb.danielramos.me/ -H 'Origin: app://obsidian.md' -H 'Access-Control-Request-Method: GET' -i` → cabeceras `Access-Control-Allow-Origin: app://obsidian.md` y `Access-Control-Allow-Credentials: true`.

---

### Fase 4 — Configurar Obsidian LiveSync (cliente) + sync end-to-end

**Objetivo:** validar la sincronización real entre dispositivos. Paso del lado del usuario; se documentan los valores.

1. En Obsidian, plugin **Self-hosted LiveSync** → Remote Database:
   - URI: `https://couchdb.danielramos.me`
   - Database name: `obsidian-vault`
   - Username: `obsidian` / Password: el elegido en Fase 0.
2. "Check database configuration" en el plugin → todo en verde (el plugin valida CORS/permisos).
3. Sincronizar desde un 2º dispositivo (móvil/fuera de casa) y confirmar replicación bidireccional.

---

### Fase 5 — Cierre

1. Marcar los Acceptance Criteria cumplidos.
2. Cumplir el DoD: **desplegar con `/deploy`**.
3. Pedir aprobación explícita del usuario antes de poner la tarea en `Done` y commitear (regla del CLAUDE.md).
4. La tarea de backups (NASKS-72) queda fuera de scope, ya creada.

---

### Mapeo Fase → Acceptance Criteria

| Fase | ACs cubiertos |
|---|---|
| 0 | #2 (imagen/versión), #4 (secretos) |
| 1 | #1 (módulo + wiring), #3 (storage), #4 (admin env + COUCHDB_SECRET), #5 (config), #7 (probe TCP) |
| 2 | #8 (job de migración) |
| 3 | #6 (ingress orange sin Authelia), #9 (DNS) |
| — | #10 (sin backups — decisión, nada que implementar) |

### Riesgos / puntos a confirmar antes de implementar

1. **Límites de tamaño** (`max_http_request_size` = 100 MB, `max_document_size` = 50 MB): elegidos para alinear con el techo de Cloudflare (orange) frente a los 4 GB / 50 MB que recomienda LiveSync. Riesgos: (a) un request en el límite exacto de 100 MB podría rechazarse en el origen si CF lo deja pasar — quizá fijar el origen algo por encima (p. ej. 128 MB) y dejar que CF sea el único techo; (b) `max_document_size=50 MB` rechazaría un documento de 50–100 MB aunque el HTTP lo permita. LiveSync trocea, así que probablemente irrelevante. **Confirmar valores con el usuario.**
2. **Init container de permisos:** asumido necesario (imagen corre como uid 5984 sobre hostPath root). Validar en el deploy de Fase 1; si el hostPath ya tiene permisos correctos, eliminarlo.
   - ✅ **Verificado (Context7 `/apache/couchdb`):** `[couchdb] single_node=true` auto-crea `_users`/`_replicator`/`_global_changes` al arrancar (CouchDB 3.0+). Por eso el job de migración NO necesita crear las system DBs, solo `obsidian-vault` + usuario + `_security`.
3. **Tag exacto de la imagen** `apache/couchdb` 3.x estable y de `curlimages/curl`: verificar contra el registry al implementar.
4. **`curl` en el job:** se usa `curlimages/curl` (la imagen oficial de CouchDB no garantiza traer curl).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Desplegado y verificado end-to-end. Commits: `feat(couchdb)` + `fix(couchdb): run as uid 5984` + `style(couchdb): tk fmt`.

### Archivos
- `lib/databases/couchdb/couchdb.libsonnet` — StatefulSet (hostPath `/data/couchdb`, init `fix-perms` root, probe TCP 5984, env admin desde SealedSecret strict), Service, ConfigMap del `.ini`, Job de migración idempotente y IngressRoute orange sin Authelia.
- `lib/databases/couchdb/couchdb.config.ini` — solo los deltas de LiveSync + `single_node = true`.
- `lib/databases/couchdb/couchdb.create-user.sh` — POSIX sh (imagen `curlimages/curl`, sin bash), idempotente vía códigos HTTP (412/409 tolerados, 5xx falla).
- `lib/databases/couchdb/couchdb.secrets.json` — strict, ns `databases`: `couchdb` (USER/PASSWORD/SECRET) + `userObsidian` (string sellado plano).
- `lib/versions.json` — `couchdb` 3.5.2, `curl` 8.21.0. `environments/databases/main.jsonnet` — `couchdb.new()`.

### Decisiones / desvíos respecto al plan
- **Límites de tamaño:** el plan/AC#5 proponía ≈100 MB; el usuario decidió usar los **recomendados por LiveSync** (`max_http_request_size = 4 GB`, `max_document_size = 50 MB`) para que Cloudflare (100 MB en orange) sea el único cuello de botella y estar preparados si CF sube el límite.
- **`_security`:** `obsidian` se puso como **admin local de su DB** además de member (no solo member como decía el plan), porque LiveSync necesita crear design docs/índices ("Check database configuration"). Sigue aislado del resto de DBs.

### Gotcha crítico resuelto (causa del primer CrashLoopBackOff)
El entrypoint oficial de `apache/couchdb`, **si arranca como root**, hace `chown -R` sobre `/opt/couchdb` e intenta chownear nuestro `couchdb.config.ini` (montaje de ConfigMap **read-only / EROFS**). El `chown` falla y, bajo `set -e`, el entrypoint **aborta antes de escribir el admin o arrancar couchdb** → el contenedor salía con código 1 y **cero logs** (la VM de Erlang ni llegaba a inicializar el logger). Solución: `securityContext` de pod con `runAsUser/runAsGroup/fsGroup = 5984`, de modo que `id -u != 0` y el bloque de `chown` se salta. El init `fix-perms` conserva `runAsUser: 0` (override) para chownear el hostPath de datos, que sigue siendo necesario.

### Verificación
- Interno (Service): `/_up` 401 sin auth / 200 con auth; `/_all_dbs` = `_replicator`,`_users`,`obsidian-vault`; `_security` correcto; usuario `obsidian` en `_users`.
- Externo (`https://couchdb.danielramos.me`): DNS → IPs de Cloudflare (orange), HTTPS 401 con `server: cloudflare` + `cf-ray`, `WWW-Authenticate: Basic realm="couchdb"`, y preflight CORS para `app://obsidian.md` con allow-origin/credentials/methods/headers correctos.

### Pendiente (lado usuario, Fase 4)
Configurar el plugin Self-hosted LiveSync (URI `https://couchdb.danielramos.me`, DB `obsidian-vault`, usuario `obsidian` + su password), pulsar "Check database configuration" y validar sync entre dispositivos.
<!-- SECTION:NOTES:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Módulo CouchDB creado en lib/databases/couchdb/couchdb.libsonnet siguiendo el patrón new(version), y añadido a environments/databases/main.jsonnet con u.labelApp() para que ArgoCD lo recoja
- [x] #2 Desplegado como StatefulSet/Deployment con imagen apache/couchdb 3.x estable, tag fijado en versions.json (no latest)
- [x] #3 Almacenamiento hostPath en /data/couchdb (SSD)
- [x] #4 Admin bootstrapeado vía COUCHDB_USER/COUCHDB_PASSWORD desde SealedSecret (scope strict, namespace databases), más COUCHDB_SECRET fijado por env para persistir sesiones entre reinicios
- [x] #5 Config local.ini mínima con solo los deltas que LiveSync exige: require_valid_user = true, CORS con origins app://obsidian.md,capacitor://localhost,http://localhost, y límites de tamaño (decisión final del usuario: los recomendados por LiveSync — max_http_request_size = 4 GB, max_document_size = 50 MB — para que Cloudflare sea el único techo; valores verificados contra la doc oficial de LiveSync)
- [x] #6 Exposición vía u.ingressRoute.from(service, 'couchdb.danielramos.me') orange-proxied por Cloudflare, sin middleware de Authelia ni rate-limit/Crowdsec propios
- [x] #7 Probe TCP al puerto 5984 (no HTTP, porque require_valid_user=true devuelve 401 en /_up)
- [x] #8 Job de migración declarativo idempotente (estilo mariadb.create-user.sh) que crea la database obsidian-vault, el usuario no-admin obsidian en _users, y el _security de la database para darle acceso solo a esa DB
- [x] #9 Registro DNS couchdb.danielramos.me creado en Cloudflare como proxied (orange) — paso manual documentado
- [x] #10 Sin backups dedicados (se gestiona en una tarea aparte)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Desplegar con /deploy
<!-- DOD:END -->
