---
id: NASKS-66
title: Desplegar Mautrix-WhatsApp bridge (backup mensajes)
status: In Progress
assignee: []
created_date: '2026-06-19 17:02'
updated_date: '2026-06-19 20:58'
labels:
  - app
  - system
  - refined
dependencies:
  - NASKS-64
references:
  - 'https://github.com/mautrix/whatsapp'
  - 'https://docs.mau.fi/bridges/go/whatsapp/index.html'
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## TL;DR

Desplegar el bridge **Mautrix-WhatsApp** junto a Synapse (NASKS-64) en k3s/Tanka para archivar los mensajes de WhatsApp en el NAS. Bridge *puppeted*, con e2ee, backfill al máximo y appservice cableado vía `registration.yaml` pre-generado como SealedSecret (propiedad de Synapse). Se ejecuta en **5 fases** independientes (cambio → deploy → revisar), aislando el cambio delicado sobre Synapse. Detalles finos cerrados en *Implementation Notes* (dry-run).

## Contexto funcional

Archivo continuo de mis mensajes de WhatsApp en el NAS: cada mensaje queda persistido y consultable desde Element. Acceso una sola vez por QR con `@whatsappbot:matrix.danielramos.me`. Admin del bridge: **`@dani:matrix.danielramos.me`** (único usuario en Synapse, verificado en Postgres).

**Límite del historial**: el backfill solo trae lo que WhatsApp sincroniza al vincular dispositivo (meses recientes, no años). No es limitación nuestra ni de mautrix. Historial más antiguo → ver "fuera de alcance" en notas (export crudo como archivo frío; descartados rollback a 1.87/MSC2716 e inyección como eventos nuevos).

## Contexto técnico

### Arquitectura
```
WhatsApp (móvil) ──QR──► mautrix-whatsapp ──appservice (as/hs_token)──► synapse (communications)
                          Deployment, escucha 0.0.0.0:29318                     │
                          DB: mautrixwhatsapp @ postgres.databases              ▼
                                                                         postgres.databases
```
Ambos pods en `communications`. `homeserver.domain` del bridge == `server_name` de Synapse (`matrix.danielramos.me`), exacto.

### Estado actual de Synapse (verificado)
- v1.155.0, Deployment, init `envsubst` renderiza `homeserver.yaml`, Postgres (DB/user `synapse`), media hostPath, `data` emptyDir, OIDC Authelia, signing key SealedSecret.
- **NO existe `app_service_config_files`** → se añade en Fase 3.

### Decisiones de diseño (cerradas)
1. **e2ee ON** (`encryption.allow + default: true`). El secreto descifrable es `encryption.pickle_key`. Se genera `openssl rand -hex 32`, se sella (strict) y se entrega al usuario por fichero `/tmp/*.txt` (hex copiable a Apple Passwords). **Claude nunca lo imprime ni lo lee con Read; solo `cat | encrypt`.** Bridge arranca con `--no-update` para que NO reescriba el config (reescribir regeneraría pickle_key → mensajes ilegibles).
2. **Backfill al máximo**: `request_full_sync: true`, `max_initial_conversations: -1`, `max_initial_messages`/`max_catchup_messages` altos.
3. **registration.yaml**: tokens `as_token`/`hs_token` generados con `openssl rand -hex 32`, registration escrito a mano, sellado como fichero (strict). **Propiedad de Synapse** (declarado en `synapse.libsonnet`); el bridge lo monta por nombre → Fase 3 autocontenida.
4. **Render por envsubst** (patrón vivo del repo, no jq-merge): ConfigMap público con `${AS_TOKEN}`/`${HS_TOKEN}`/`${PICKLE_KEY}`/`${DB_PASSWORD}`.
5. **Naming canónico**: rol+DB+URI = `mautrixwhatsapp` (sin guion). Bridge sin hostPath/PVC (estado en Postgres).

### Componentes
- **Postgres**: DB+user `mautrixwhatsapp` (skill `add-new-ddbb-user`).
- **`lib/communications/mautrix-whatsapp/`**: `.libsonnet` (Deployment, Service :29318, init envsubst, **2 SealedSecrets**: strict AS/HS/PICKLE + cluster-wide DB), `config.yaml`, `.secrets.json`.
- **`lib/communications/synapse/`**: `app_service_config_files` + monta el registration SealedSecret (que declara Synapse).
- **`lib/versions.json`**: `mautrixWhatsapp` → `dock.mau.dev/mautrix/whatsapp` (tag fijo, no latest).
- **ArgoCD**: `u.labelApp()` autogenera la Application.

## Criterios de aceptación

Trackeados en *Acceptance Criteria* (10 ítems): DB sin errores, registration sellado en ambos pods, tokens sellados, e2ee+pickle_key entregado, backfill al máximo, admin `@dani`, login QR, mensajes en Element, persistencia tras reinicio, ArgoCD healthy.

## PLAN

### Protocolo de ejecución por fase (LEER — la próxima sesión debe seguirlo)

Cada fase con cambios en repo sigue este ciclo, **parando en la verja de revisión**:

1. **Cambio**: editar los ficheros de la fase. Validar que compila: `tk eval environments/<env> | tail -2` (termina en `}`).
2. **🚦 VERJA DE REVISIÓN (obligatoria)**: mostrar `git diff` al usuario y **esperar su OK explícito ANTES de cualquier commit/PR**. No se commitea nada sin que el usuario haya revisado el código.
3. **Deploy** (solo si la fase despliega — ver tabla): tras el OK, usar la skill **`/deploy`** (branch → PR → CI verde → squash merge → ArgoCD auto-sync por webhook). **NUNCA `argocd app sync` manual ni `tk apply`.**
4. **Revisar/verificar**: comprobar el resultado en cluster (Loki/psql/Element) según los criterios de la fase antes de pasar a la siguiente.

**Qué fase despliega:**

| Fase | ¿Deploy? | Commit |
|------|----------|--------|
| 1 — DB Postgres | **Sí** (app `postgres`) | propio |
| 2 — Bootstrap secretos | No (solo sella blobs) | los blobs se commitean junto a la fase que los consume: registration→Fase 3, secretos del bridge→Fase 4 |
| 3 — Synapse registration | **Sí** (app `synapse`) | propio (incluye el SealedSecret del registration de Fase 2) |
| 4 — Deploy del bridge | **Sí** (app `mautrix-whatsapp`) | propio (incluye los SealedSecrets del bridge de Fase 2) |
| 5 — Login + verificación | No (acción manual en Element) | — |

### Fase 1 — DB en Postgres (riesgo nulo)
- **Cambio**: `add-new-ddbb-user` → `userMautrixWhatsapp` en `postgres.libsonnet`+`.secrets.json` (rol/DB `mautrixwhatsapp`).
- **🚦 Revisión + Deploy** (`/deploy`, app `postgres`). **Revisar**: job `postgres-create-user-mautrixwhatsapp` Completed; `psql -tAc "SELECT rolname FROM pg_roles..."`; Loki sin errores.

### Fase 2 — Bootstrap de secretos (local, sin deploy)
- `openssl rand -hex 32` → as_token, hs_token, pickle_key (a `/tmp/*.txt`). Escribir `registration.yaml` a mano con esos tokens (ver skeleton en notas).
- Cifrar (orden importa, nombres exactos = `metadata.name` del recurso): registration como fichero strict; AS/HS/PICKLE como env strict; DB ya está cluster-wide de Fase 1. **as/hs se cifran 2 veces (registration + config) desde el mismo `/tmp`.**
- Entregar pickle_key al usuario; `rm -f /tmp/*.txt`. Sin deploy.

### Fase 3 — Synapse referencia el registration (⚠️ aislado)
- **Cambio**: declarar el registration SealedSecret en `synapse.libsonnet` + volumen + mount en `/appservice` + `app_service_config_files: [/appservice/registration.yaml]` en `homeserver.yaml`. Bridge aún no existe.
- **🚦 Revisión + Deploy** (`/deploy`, app `synapse`). El commit incluye el SealedSecret del registration sellado en Fase 2. **Revisar**: Synapse Running + startup probe verde; carga el registration sin error de parseo/regex (un namespace/regex mal → NO arranca); warning "appservice no contactable" = esperado. Si rompe → revert del PR.

### Fase 4 — Desplegar el bridge
- **Cambio**: `lib/communications/mautrix-whatsapp/` (config envsubst con `appservice.address`=svc DNS y `hostname`=0.0.0.0, `bridge.permissions @dani: admin`, DB URI a `mautrixwhatsapp`, e2ee+pickle, backfill máximo), montar registration por nombre, `main.jsonnet` + `versions.json`. Arranque `-c <render> -r <reg> --no-update`.
- **🚦 Revisión + Deploy** (`/deploy`, app `mautrix-whatsapp`). El commit incluye los SealedSecrets del bridge sellados en Fase 2. **Revisar**: pod Running, conecta DB sin errores; Synapse loguea appservice **conectado**; ArgoCD synced/healthy. Sin login aún.

### Fase 5 — Login WhatsApp + verificación (manual)
- DM a `@whatsappbot` → `login qr` → escanear.
- **Revisar**: mensajes en Element, e2ee activo (candado; `SELECT count(*) FROM crypto_megolm_inbound_session` > 0), backfill corre, persisten tras `rollout restart` de bridge+synapse.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Mautrix-WhatsApp bridge corriendo; DB `mautrixwhatsapp` creada en Postgres sin errores en Loki
- [ ] #2 `registration.yaml` gestionado como SealedSecret pre-generado (`registration-yaml-sealed-secret`, propiedad de Synapse) y montado en ambos pods; Synapse lo referencia en `app_service_config_files`
- [ ] #3 Tokens (as_token/hs_token) y demás secretos del bridge gestionados como SealedSecret
- [ ] #4 e2ee activado (encryption.allow + default true); `pickle_key` generado, cifrado como SealedSecret y entregado al usuario vía fichero temporal (nunca impreso en contexto)
- [ ] #5 Backfill configurado al máximo (backfill.* + network.history_sync.request_full_sync), asumiendo el límite que impone WhatsApp (~3 años)
- [ ] #6 Admin del bridge = @dani:matrix.danielramos.me en bridge.permissions
- [ ] #7 Login con `@whatsappbot`: QR escaneado desde el móvil → sesión activa
- [ ] #8 Mensajes de WhatsApp aparecen en el cliente Matrix (Element u otro)
- [ ] #9 Mensajes persisten en Postgres tras reinicio de pods (legibles conservando el pickle_key)
- [ ] #10 Application de ArgoCD synced healthy
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Historial antiguo (fuera del alcance del bridge)

El backfill del bridge está limitado por lo que WhatsApp sincroniza al vincular dispositivo (meses recientes), no por la versión de Synapse. Para el historial más antiguo:

- **Descartado**: rollback de Synapse a v1.87.0 + MSC2716. No aumenta la cantidad de datos (el techo es de WhatsApp, no de Synapse), solo afecta a la colocación cronológica. Además: migraciones de schema de un solo sentido, import MSC2716 experimental/frágil, mautrix antiguo posiblemente incapaz de loguear en WhatsApp actual, y riesgo de state-reset al re-upgradear.
- **Descartado**: import del export `.txt` como eventos nuevos (rompe cronología, ensucia rooms).
- **Recomendado y complementario**: guardar el export crudo de WhatsApp (`.txt` + media) como archivo frío en `/cold-data/...`, fuera de Matrix. Fiel pero no consultable desde Matrix. Tarea futura aparte si se quiere automatizar.

Referencias verificadas (jun 2026): MSC2716 abandonado; Synapse dejó de soportarlo en v1.87.0 (jul 2023); corremos v1.155.0.

## Detalles cerrados del dry-run (16 huecos)

### Los 5 valores que DEBEN casar entre registration.yaml y config.yaml
1. `as_token` == `appservice.as_token`
2. `hs_token` == `appservice.hs_token`
3. `registration.id` == `appservice.id` (= `whatsapp`)
4. `registration.sender_localpart` == `appservice.bot.username` (= `whatsappbot`)
5. `registration.namespaces.users` regex casa con `appservice.username_template` (`whatsapp_{{.}}`) e incluye al bot. Regex/namespace mal formado → Synapse NO arranca.

### Skeleton registration.yaml (Fase 2, escrito a mano)
```yaml
id: whatsapp
url: http://mautrix-whatsapp.communications.svc.cluster.local:29318
as_token: <as_token.txt>
hs_token: <hs_token.txt>
sender_localpart: whatsappbot
rate_limited: false
namespaces:
  users:
    - regex: '@whatsapp_.*:matrix\.danielramos\.me'
      exclusive: true
    - regex: '@whatsappbot:matrix\.danielramos\.me'
      exclusive: true
```

### Campos NO-default del config.yaml del bridge (Fase 4, envsubst)
```yaml
homeserver: { address: http://synapse.communications.svc.cluster.local:8008, domain: matrix.danielramos.me, software: standard }
appservice:
  address: http://mautrix-whatsapp.communications.svc.cluster.local:29318  # como llega Synapse (= registration.url)
  hostname: 0.0.0.0   # donde ESCUCHA (NO 127.0.0.1 default)
  port: 29318
  id: whatsapp
  bot: { username: whatsappbot, displayname: WhatsApp bridge bot }
  username_template: whatsapp_{{.}}
  ephemeral_events: true
  as_token: ${AS_TOKEN}
  hs_token: ${HS_TOKEN}
database: { type: postgres, uri: 'postgres://mautrixwhatsapp:${DB_PASSWORD}@postgres.databases.svc.cluster.local/mautrixwhatsapp?sslmode=disable' }
bridge: { permissions: { '@dani:matrix.danielramos.me': admin } }
backfill: { enabled: true, max_initial_messages: 10000, max_catchup_messages: 10000 }
encryption: { allow: true, default: true, pickle_key: ${PICKLE_KEY} }
network: { history_sync: { request_full_sync: true, max_initial_conversations: -1 } }
```
NOTA: confirmar nombres exactos de campos backfill/history_sync y el flag de arranque (`--no-update`, `-r`) contra `--help` de la versión de imagen elegida antes de implementar.

### Resoluciones clave
- #1 registration **propiedad de Synapse** (synapse.libsonnet); bridge lo monta por nombre → Fase 3 autocontenida.
- #2/#6 as/hs generados una vez (`openssl rand -hex 32`), cifrados 2 veces (registration fichero strict + config env strict) desde el mismo `/tmp` antes de borrar.
- #4 nombre del SealedSecret = `metadata.name` exacto que genera `forFile`/`forEnvNamed`; derivarlo de `normalizeName` antes de `encrypt-secret.sh`.
- #8/#11 bridge con 2 SealedSecrets: strict (AS/HS/PICKLE) + cluster-wide (DB_PASSWORD, de Fase 1). No mezclar scopes.
- #4-render envsubst (no jq); `--no-update` para no regenerar pickle_key.
- #16 bridge sin hostPath/PVC: estado (sesión WA + claves e2ee) en Postgres → emptyDir basta.
- #10 password hex → sin URL-encoding necesario.
- #15 nunca `Read` sobre /tmp/*.txt; solo `cat | encrypt`; `rm -f` al final.
- #14 fijar tag concreto de dock.mau.dev/mautrix/whatsapp (no latest).

## Segunda pasada del dry-run (validado contra código fuente de mautrix)

**Veredicto**: Fases 1-3 listas para arrancar tal cual. 1 bloqueante para Fase 4 (H1) y ajustes finos. Confirmaciones autoritativas (leído el código, no solo doc).

### Correcciones a aplicar al implementar

**H1 (CRÍTICO, Fase 4) — override del entrypoint del contenedor.** El `docker-run.sh` de la imagen arranca `mautrix-whatsapp` sin flags y hace `yq -i` que MUTA `/data/config.yaml` + `chown -R /data`. Hay que bypassear el entrypoint:
```jsonnet
container.withCommand(['/usr/bin/mautrix-whatsapp', '-c', '/data/config.yaml', '-r', '/data/registration.yaml', '-n'])
```
con `/data` = emptyDir **writable** (init envsubst escribe ahí el config.yaml renderizado; el registration va por subPath del Secret). `-n`/`--no-update` evita que reescriba el config (preserva pickle_key). Flags verificados en `bridgev2/matrix/mxmain/main.go`.

**H2 (importante) — ephemeral en el registration.** Con `appservice.ephemeral_events: true`, el registration hecho a mano debe incluir `de.sorunome.msc2409.push_ephemeral: true` o Synapse no empuja typing/receipts/presence al bridge.

**H3 (importante) — regex anclados.** Usar `^...$` (mautrix los ancla; sin `$`, `@whatsappbot2:...` colisiona namespaces exclusivos → Synapse puede no arrancar).

**H4 (importante) — `/data` writable.** NO aplicar `readOnly: true` al volumen `/data`; solo el subPath del registration puede ser efImero.

### registration.yaml CORREGIDO (reemplaza al skeleton anterior)
```yaml
id: whatsapp
url: http://mautrix-whatsapp.communications.svc.cluster.local:29318
as_token: <as_token.txt>
hs_token: <hs_token.txt>
sender_localpart: whatsappbot
rate_limited: false
de.sorunome.msc2409.push_ephemeral: true
namespaces:
  users:
    - regex: '^@whatsapp_.*:matrix\.danielramos\.me$'
      exclusive: true
    - regex: '^@whatsappbot:matrix\.danielramos\.me$'
      exclusive: true
```

### Confirmaciones empIricas
- Nombre SealedSecret registration = **`registration-yaml-sealed-secret`** (verificado `tk eval`; `.`/`_` → `-` en normalizeName). Pasar ese literal a `encrypt-secret.sh communications registration-yaml-sealed-secret`.
- Bridge monta el Secret por nombre sin re-declararlo: `volume.fromSecret('registration-yaml-sealed-secret','registration-yaml-sealed-secret')` + `volumeMount.new(...,'/data/registration.yaml')+withSubPath('registration.yaml')`. No duplica recurso → sin conflicto SSA. (NOTA: el bridge no puede usar el helper `fromSealedSecretFile` porque ese espera el OBJETO; usar los helpers de k8s-libsonnet con el literal.)
- Synapse monta el registration en el contenedor principal (no el init) en `/appservice/registration.yaml` (subPath), sin pasar por envsubst.
- Campos verificados (example-config bridgev2 + whatsapp connector): `backfill.{enabled,max_initial_messages(50),max_catchup_messages(500)}`; `network.history_sync.{request_full_sync(false),max_initial_conversations(-1),full_sync_config.days_limit}`; `encryption.pickle_key(default generate)`. Skeleton coincide.
- Tag estable a fijar: **`v0.2606.0`**.
- Naming: directorio/Deployment/Service/DNS = `mautrix-whatsapp` (CON guion); solo role/DB/URI-postgres = `mautrixwhatsapp` (sin guion). `serviceFor` nombra el Service igual que el Deployment → Deployment DEBE llamarse `mautrix-whatsapp`.

### Menores
- H5: para backfill máximo de verdad, considerar `network.history_sync.full_sync_config.days_limit` alto (techo WhatsApp ~3 años).
- H7: `create-user.sh` crea extensiones vector/cube/etc. en la DB (inofensivo, compartido por todas las DBs).

## Tercera pasada — GO (go/no-go final)

**Veredicto: GO.** Sin bloqueantes críticos nuevos. Riesgo principal (envsubst vs `{{.}}`) DESCARTADO empíricamente: el `homeserver.yaml` de Synapse YA contiene `{{ user.preferred_username }}` etc., pasa por el mismo `envsubst` (bhgedigital/envsubst sin args) y corre healthy con OIDC → los `{{ }}` sobreviven. envsubst solo toca `${VAR}`. Patrón probado en producción. Fases 1-3 listas; residuales solo de implementación (Fase 4).

### Residuales (resolver al implementar, no bloquean Fase 1)
- **R1 (imp)** Probe del bridge: NO expone health HTTP. Usar `u.probes.tcp(29318)` (patrón invidious-companion), no `withStartup.http`.
- **R2 (imp)** Fase 2: el cifrado del registration sella el `registration.yaml` ENTERO (tokens embebidos), distinto de cifrar AS/HS como env vars sueltas del SealedSecret del bridge. Ambos del mismo `/tmp`.
- **R3 (imp)** El Deployment DEBE declarar `containerPort.new('appservice', 29318)` o `serviceFor` no genera el puerto → el DNS `:29318` no resuelve → Synapse no contacta el appservice.
- **R4 (menor)** bridgev2 no trae `metrics` por defecto. Omitir `u.metrics` salvo activar `metrics.enabled/listen` en config + containerPort dedicado.
- **R5 (menor)** No introducir `$` literales en el config.yaml fuera de los 4 placeholders (`${AS_TOKEN}/${HS_TOKEN}/${PICKLE_KEY}/${DB_PASSWORD}`); envsubst sin args vaciaría `$word`. Password hex evita el caso del URI.

### Wiring confirmado (compila)
- `u.Environment` aplica `kebabCase` a la KEY → key `mautrixWhatsapp` en main.jsonnet da label/Deployment/Service/DNS = `mautrix-whatsapp`. ✅
- Fase 1: en postgres.libsonnet `userMautrixWhatsapp: self.createUser('mautrixwhatsapp', secrets.userMautrixWhatsapp, ...)` (key camelCase, rol/DB lowercase).
- Bridge init env: `u.envVars.fromSealedSecret(self.sealedSecret) + u.envVars.fromSealedSecret(self.sealedSecretDb)` (patrón synapse.libsonnet:37-40).
- versions.json key `mautrixWhatsapp` → `{image: dock.mau.dev/mautrix/whatsapp, version: v0.2606.0}`.
- ArgoCD autogenera la app `mautrix-whatsapp` (argocd/main.jsonnet importa communications). ✅

### No verificado (honesto)
- Config renderizado dentro del pod (no inspeccionado: traería secretos a contexto). Inferencia estructural sólida.
- Nombres exactos `backfill.request_full_sync`/`max_initial_conversations` campo a campo en v0.2606.0: red de seguridad = confirmar contra example-config de la versión antes de Fase 4 (ya anotado).
<!-- SECTION:NOTES:END -->
