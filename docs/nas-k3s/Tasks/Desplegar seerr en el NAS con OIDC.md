---
title: "Desplegar seerr en el NAS con OIDC"
status: In Progress
priority: 2
labels: [seerr, oidc, media]
parent:
dependencies: "[[Imagen propia de seerr con OIDC (PR 2715)]]"
references:
  - "https://github.com/seerr-team/seerr/pull/2715"
  - "https://docs.seerr.dev/getting-started/docker"
  - "https://github.com/michaelhthomas/seerr/blob/feat/oidc-login-basic/docs/using-seerr/settings/users/oidc.md"
created_date: 2026-10-12 10:42
---

## Description

## 📌 TLDR

Desplegar seerr en el clúster k3s usando nuestra imagen `ghcr.io/danielramosacosta/seerr:oidc-pr2715` (HEAD del PR #2715), expuesto en `seerr.danielramos.me` vía Traefik, y configurar login OIDC contra Authelia.

## 🎯 Contexto funcional

seerr (fork de Overseerr/Jellyseerr) gestiona peticiones de medios. Queremos probar el PR de OIDC para integrar el login con nuestra Authelia como el resto de servicios. Servicio nuevo en el homelab, módulo creado de cero en `lib/media/`.

## ⚙️ Contexto técnico

### Runtime (de la doc oficial de Docker)
- Imagen: `ghcr.io/danielramosacosta/seerr`, versión pinada por **sha corto** en `versions.json` (Opción B / GitOps). El workflow del fork taguea `sha-<short>` (+ `oidc-pr2715` flotante). Nota: el sha es el HEAD de `homelab-build` (= código del PR + 2 commits del workflow; los `.github/` no entran en la imagen), no el hash literal del commit del PR. Actualizar PR = rebase de `homelab-build` → nuevo sha → bump `versions.json` → `/deploy` (ArgoCD redespliega).
- Corre como usuario `node` **UID 1000** → `runAsUser: 1000`, `runAsGroup: 1000`.
- Puerto **5055** (HTTP). Service ClusterIP → IngressRoute `seerr.danielramos.me` con TLS Let's Encrypt.
- **IngressRoute plano SIN forward-auth de Authelia** (seerr es cliente OIDC, no recurso protegido; un forward-auth bloquearía el callback OIDC). Estilo navidrome/jellyfin: `u.ingressRoute.from(self.service, 'seerr.danielramos.me')` — sin middlewares. `u.ingressRoute.from` ya aplica `entryPoints: [websecure]` + `tls.store: default` (cert wildcard). La geo-protección va en el **edge de Cloudflare** (orange-cloud), como el resto de servicios; las defensas geoblock/crowdsec de immich son específicas suyas (va gray-cloud).
- **DNS**: `cloudflare-ddns` solo refresca `nas.danielramos.me`; asegurar que `seerr.danielramos.me` resuelve (wildcard `*.danielramos.me` o CNAME nuevo → `nas.danielramos.me`, orange-cloud).
- Env: `TZ` (zona horaria), `LOG_LEVEL` (opcional, `info`), `PORT` (opcional, default 5055).
- Healthcheck: `GET /api/v1/settings/public`.
- Endurecimiento del contenedor: `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`.

**Defaults mecánicos asumidos:**
- `Deployment` (no StatefulSet), `replicas: 1` — convención de las apps de `lib/media/` (salvo invidious).
- **Sin** `resources` requests/limits explícitos — como el resto de apps media del repo.
- `DB_TYPE=postgres` **obligatorio** (verificado: `server/utils/dbType.ts` → `isPgsql = process.env.DB_TYPE === 'postgres'`; sin él, seerr usa SQLite y no toca Postgres).

### Persistencia — SÍ, un único volumen (aunque la BBDD sea externa)
- **`/app/config`** (hostPath, p. ej. `/data/seerr`). Único volumen a montar. Con Postgres ya NO contiene la base de datos, pero sigue conteniendo estado mutable que hay que persistir:
  - `settings.json` — configuración (incluida la de OIDC) + API key que seerr autogenera.
  - logs y caché.
- El dir lo escribe la app (UID 1000) → fijar owner en el host una vez: `sudo chown -R 1000:1000 /data/seerr` (patrón del repo para apps non-root sobre hostPath; `fsGroup` no aplica a hostPath).

### Base de datos — DECISIÓN: PostgreSQL (clúster compartido)
- Se usa el Postgres compartido del clúster. Crear BBDD + usuario con la skill **`add-new-ddbb-user`** (BBDD `seerr`).
- Configuración vía env vars (conexión TCP):
  - `DB_HOST` → service del Postgres compartido
  - `DB_PORT=5432`
  - `DB_USER` (requerido) — el que cree la skill
  - `DB_PASS` (requerido) — **secreto**, vía SealedSecret (patrón cluster-wide compartido de contraseñas de BBDD)
  - `DB_NAME=seerr`
  - (seerr detecta Postgres por la presencia de `DB_HOST`/`DB_USER`; confirmar si hace falta además un `DB_TYPE=postgres` al arrancar — Jellyseerr lo requería).

### Secretos — DOS
1. **`DB_PASS`** — contraseña del usuario de Postgres. SealedSecret (la skill `add-new-ddbb-user` gestiona el cifrado).
2. **Client Secret de OIDC** — lo emite Authelia al registrar el cliente `seerr`.
   - ⚠️ Authelia almacena el **digest hasheado** (`..._CLIENT_SECRET_DIGEST`), pero seerr necesita el **secreto en claro** en su `settings.json`. Hay que conservar el valor en claro (sin pasarlo por el contexto de Claude) para meterlo en seerr, además del digest que va a Authelia.
   - Matiz importante: en este PR el OIDC se configura **a mano en `settings.json`** (aún no hay UI), y `settings.json` lo **reescribe la app** en runtime. No encaja con el patrón ConfigMap read-only del repo. Opciones a decidir:
     - (a) Arrancar seerr, hacer el setup inicial, y **editar `settings.json` en el hostPath** añadiendo el bloque `oidc` + reinicio (Reloader no aplica porque no es un ConfigMap). Simple para un test.
     - (b) Init container que haga merge (jq) de un `settings.json` base + un SealedSecret con el `clientSecret` **solo en el primer arranque** (seerr lo reescribirá luego). Más "GitOps" pero frágil porque la app sobrescribe el fichero.

### OIDC (config del PR en `settings.json`)
```json
"oidcLogin": true,
"oidc": {
  "providers": [{
    "slug": "authelia",
    "name": "Authelia",
    "issuerUrl": "https://auth.danielramos.me",  // confirmado
    "clientId": "seerr",
    "clientSecret": "<secret>",
    "logo": "...",
    "scopes": "openid profile email",
    "newUserLogin": true
  }]
}
```
- Redirect URIs a registrar en el cliente de Authelia:
  - `https://seerr.danielramos.me/login`
  - `https://seerr.danielramos.me/profile/settings/linked-accounts`
- Issuer URL = base de Authelia: **`https://auth.danielramos.me`** (confirmado).
- Cliente usa `openid-client` v6 con **PKCE** → en Authelia: `require_pkce: true`, `pkce_challenge_method: 'S256'`, `token_endpoint_auth_method: 'client_secret_basic'` (default de la librería al pasar clientSecret). `client_id` legible = `seerr` (va a `settings.json` a mano, mejor no un random de 72 chars). No hay guía oficial de Authelia para seerr → registro manual siguiendo el patrón genérico del repo + redirect URIs de `oidc.md`.
- Usar la skill `integrate-new-oidc-service` para registrar el cliente en Authelia.

### Login: objetivo "solo OIDC" + bootstrap del owner
seerr tiene 3 toggles independientes en `settings.main`: `localLogin` (email/pass), `mediaServerLogin` (Plex/Jellyfin), `oidcLogin`. Defaults: local+mediaServer `true`, oidc `false`. Objetivo: dejar **solo** `oidcLogin: true`.

**Pero el owner NO se puede crear por OIDC** (verificado en `server/routes/auth.ts` del PR): el callback OIDC crea usuarios con `defaultPermissions` y no tiene lógica de "primer usuario = admin". El owner (id 1, `Permission.ADMIN`) solo se crea por la ruta de media server (Jellyfin/Plex) en el setup. Secuencia obligada:
1. Setup inicial conectando **Jellyfin** → login admin Jellyfin → crea el owner de seerr.
2. Activar `oidcLogin` + configurar proveedor Authelia.
3. **Vincular la cuenta OIDC del owner** en `/profile/settings/linked-accounts`.
4. Solo entonces `localLogin: false` + `mediaServerLogin: false`.

⚠️ **Riesgo de lockout** (mismo patrón que el SSO de Jellyfin, admin solo-SSO): si apagas local+mediaServer sin vincular OIDC al owner antes, te quedas fuera → recuperar editando `settings.json` en el hostPath. Mitigación: mantener `localLogin: true` hasta confirmar que el login OIDC del owner funciona.

**Admisión de usuarios (decidido):** `newUserLogin: true` (usuarios de Authelia = todos de confianza, se autoprovisionan) con `defaultPermissions` = solo **Request** (piden, el owner aprueba). Sin `requiredClaims`.

## Acceptance Criteria

- [ ] #1 BBDD `seerr` + usuario en el Postgres compartido creados con `add-new-ddbb-user` (incl. SealedSecret de `DB_PASS`)
- [ ] #2 Módulo Jsonnet nuevo para seerr en `lib/media/` (Deployment UID 1000, Service, IngressRoute `seerr.danielramos.me`, hostPath `/app/config`, env de Postgres) + versión en `versions.json` + alta en `environments/media/main.jsonnet`
- [ ] #3 Cliente OIDC `seerr` registrado en Authelia (`auth.danielramos.me`) con los dos redirect URIs
- [ ] #4 `settings.json` con el bloque OIDC apuntando a Authelia (método a decidir: edición manual vs init-merge)
- [ ] #5 Login OIDC contra Authelia funcionando end-to-end

## Definition of Done

- [ ] #1 desplegar con /deploy

## Implementation Plan

Ejecución **secuencial fase a fase**: implementar una fase, desplegar lo que indique, verificar su checkpoint, y solo entonces pasar a la siguiente. No adelantar código de fases posteriores.

### Fase 1 — Base de datos Postgres

1. Ejecutar la skill `add-new-ddbb-user` con nombre `seerr`:
   - Genera contraseña y la cifra cluster-wide en un pipeline (sin exponerla):
     ```bash
     openssl rand -hex 32 > /tmp/dbpass.txt && \
       cat /tmp/dbpass.txt | ./scripts/encrypt-secret.sh --cluster-wide && \
       rm -f /tmp/dbpass.txt
     ```
   - Añade la clave `userSeerr` (valor `AgC...`) a `lib/databases/postgres/postgres.secrets.json`.
   - Registra en `lib/databases/postgres/postgres.libsonnet` (sección `new()::`):
     ```jsonnet
     userSeerr: self.createUser('seerr', secrets.userSeerr, self.createUserMigration, self.sealedSecret),
     ```
2. Validar compilación: `tk eval environments/databases 2>&1 | tail -5` (termina en `}` sin errores).
3. **Desplegar** con la skill `/deploy` (entorno `databases`).
4. **Checkpoint**: en Loki (`{namespace="databases", pod=~"postgres-create-user-seerr.*"}`) el Job `postgres-create-user-seerr` corrió OK y el rol+BBDD `seerr` existen. (No continuar si el Job falló.)

### Fase 2 — Módulo seerr mínimo + arranque con Postgres

1. **host (una vez)**: `ssh nas 'sudo mkdir -p /data/seerr && sudo chown -R 1000:1000 /data/seerr'`.
2. Verificar DNS: que `seerr.danielramos.me` resuelva (wildcard `*.danielramos.me` o CNAME nuevo → `nas.danielramos.me`, orange-cloud). Si no existe, crear el registro en Cloudflare.
3. Añadir la imagen a `lib/versions.json`:
   ```json
   "seerr": { "image": "ghcr.io/danielramosacosta/seerr", "version": "sha-d2a5a2b" }
   ```
4. Crear `lib/media/seerr/seerr.libsonnet` (patrón navidrome; env Postgres como immich). Sin `secrets.json` propio (el único secreto, `DB_PASS`, viene del shared). Esqueleto:
   ```jsonnet
   local u = import '../../utils.libsonnet';
   local versions = import '../../versions.json';
   local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
   local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
   {
     local deployment = k.apps.v1.deployment,
     local container = k.core.v1.container,
     local containerPort = k.core.v1.containerPort,
     local volume = k.core.v1.volume,
     local volumeMount = k.core.v1.volumeMount,
     new():: {
       deployment: deployment.new('seerr', replicas=1, containers=[
                     container.new('seerr', u.image(versions.seerr.image, versions.seerr.version)) +
                     container.withPorts([containerPort.new('server', 5055)]) +
                     container.withEnv(
                       u.envVars.fromConfigMap(self.configEnv) +
                       u.envVars.fromSealedSecret(self.sealedSecretShared),
                     ) +
                     container.withVolumeMounts([volumeMount.new('config', '/app/config')]) +
                     container.securityContext.withAllowPrivilegeEscalation(false) +
                     container.securityContext.capabilities.withDrop(['ALL']) +
                     u.probes.withStartup.http('/api/v1/settings/public', 5055),
                   ]) +
                   deployment.spec.template.spec.securityContext.withRunAsUser(1000) +
                   deployment.spec.template.spec.securityContext.withRunAsGroup(1000) +
                   deployment.spec.template.spec.withVolumes([
                     volume.fromHostPath('config', '/data/seerr'),
                   ]),
       service: k.util.serviceFor(self.deployment),
       configEnv: u.configMap.forEnv(self.deployment, {
         DB_TYPE: 'postgres',
         DB_HOST: 'postgres.databases.svc.cluster.local',
         DB_PORT: '5432',
         DB_USER: 'seerr',
         DB_NAME: 'seerr',
         TZ: 'Europe/Madrid',
       }),
       sealedSecretShared: u.sealedSecret.wide.forEnvNamed('seerr-shared-sealed-secret', {
         DB_PASS: postgresSecrets.userSeerr,
       }),
       ingressRoute: u.ingressRoute.from(self.service, 'seerr.danielramos.me'),
     },
   }
   ```
5. Dar de alta en `environments/media/main.jsonnet`: `local seerr = import 'media/seerr/seerr.libsonnet';` + `seerr: seerr.new(),` dentro de `u.Environment({...})` (esto genera la Application de ArgoCD y estampa Reloader automáticamente).
6. Validar compilación: `tk eval environments/media 2>&1 | tail -5`.
7. **Desplegar** con la skill `/deploy` (entorno `media`).
8. **Checkpoint**: pod `seerr` `Running`; en Loki (`{namespace="media", pod=~"seerr.*"}`) las migraciones de Postgres corrieron sin error y seerr escucha en :5055; `https://seerr.danielramos.me` carga la pantalla de setup inicial.

### Fase 3 — Bootstrap del owner vía Jellyfin (config manual, sin deploy)

1. En la UI de seerr (`https://seerr.danielramos.me`), completar el wizard:
   - Media server = **Jellyfin**, URL interna `http://jellyfin.media.svc.cluster.local:8096`.
   - Login con el admin de Jellyfin → crea el owner de seerr (user id 1, `Permission.ADMIN`).
2. **Checkpoint**: el owner existe, entra al dashboard, y en `Settings → Users` se ven los tres toggles `localLogin`/`mediaServerLogin`/`oidcLogin`.

### Fase 4 — Integrar OIDC con Authelia (skill `integrate-new-oidc-service`) + config en seerr

1. Invocar la skill **`integrate-new-oidc-service`** con el servicio `seerr`. La skill genera las credenciales con el binario del pod de Authelia (sin exponerlas), añade el bloque del cliente a `authelia.config.yml`, cifra `client_id` + hash del secret en `authelia.secrets.json` y verifica el render con `tk eval | jq`. Datos seerr-específicos que hay que darle (no hay guía oficial de Authelia para seerr → se usa el fallback manual de la skill):
   - redirect_uris: `https://seerr.danielramos.me/login` y `https://seerr.danielramos.me/profile/settings/linked-accounts` (de la doc `oidc.md` del PR).
   - `require_pkce: true`, `pkce_challenge_method: 'S256'`, `token_endpoint_auth_method: 'client_secret_basic'` (openid-client v6).
   - `client_id` legible = `seerr` → **saltar el Paso 4 de la skill** (generación de client_id random). Como el cifrado 7b de la skill lee `/tmp/oidc_client_id.txt`, créalo antes con `printf 'seerr' > /tmp/oidc_client_id.txt` (o cifra directamente `printf 'seerr' | ./scripts/encrypt-secret.sh auth authelia-sealed-secret`). Generar solo el client secret (Paso 5).
   - **Lado servicio distinto a lo habitual**: seerr NO lee las credenciales por env var, así que NO se crea SealedSecret ni `seerr.secrets.json` (se **omite el Paso 7a** y el primer bloque `jq` del 7c; el `jq` del SealedSecret del servicio en el 7d devolverá vacío, no es error). El **secreto en claro** (fichero `/tmp` de la skill) se mete a mano en el `settings.json` de seerr (paso 4); en Authelia queda solo el hash.
   - **NO ejecutar el Paso 8 (limpieza) de la skill todavía**: conservar `/tmp/oidc_secret_plain.txt` hasta el paso 4.4 de esta fase; sí borrar ya el resto (`oidc_secret_hash.txt`, `oidc_client_id.txt`, `sealed_auth_*`).
   - El bloque final del cliente en `authelia.config.yml` debe llevar `consent_mode: 'implicit'` + `access_token_signed_response_alg: 'none'` + `userinfo_signed_response_alg: 'none'` (patrón del repo; la plantilla de la skill ya los incluye — verificar que quedan).
2. **Desplegar** con la skill `/deploy` (entorno `auth`). Reloader reinicia Authelia.
3. **Checkpoint**: Authelia recargó sin error de config (Loki `{namespace="auth", pod=~"authelia.*"}`) y el pod está Ready. (El cliente se valida de verdad en el primer login del paso 5 — Authelia no lista clientes en el discovery.)
4. **Config OIDC en seerr (manual, host)**: con el pod parado para que seerr no pise la edición (`kubectl -n media scale deploy/seerr --replicas=0`), editar `/data/seerr/settings.json` (vía `ssh nas`) y volver a escalar a 1. El `clientSecret` en claro se lee del `/tmp` de la skill, sin pasarlo por el contexto:
   ```json
   "oidcLogin": true,
   "oidc": { "providers": [{
     "slug": "authelia", "name": "Authelia",
     "issuerUrl": "https://auth.danielramos.me",
     "clientId": "seerr", "clientSecret": "<plano del /tmp de la skill>",
     "scopes": "openid profile email", "newUserLogin": true
   }] }
   ```
   Mantener `localLogin: true` de momento (red anti-lockout). Borrar el `/tmp` del secreto al terminar.
5. Entrar como owner (Jellyfin) → `/profile/settings/linked-accounts` → **vincular** la cuenta Authelia. Logout y probar el botón "Authelia".
6. **Checkpoint**: el login por Authelia aterriza como owner (admin); en Loki no hay `OidcProviderDiscoveryFailed`. Confirmar `defaultPermissions = Request`.
7. **Endurecer** solo tras confirmar el login OIDC del owner: `localLogin: false` + `mediaServerLogin: false` (UI o `settings.json` con scale 0/1).
8. **Checkpoint final**: solo funciona el login OIDC; el owner entra por Authelia; un segundo usuario de Authelia se autoprovisiona con permiso Request.

## Implementation Notes
