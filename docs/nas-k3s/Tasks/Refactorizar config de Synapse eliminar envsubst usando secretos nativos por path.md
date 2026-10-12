---
title: >-
  Refactorizar config de Synapse: eliminar envsubst usando secretos nativos por
  path
status: In Progress
created_date: '2026-06-19 21:50'
labels:
  - synapse
  - refactor
  - communications
dependencies: []
references:
  - lib/communications/synapse/synapse.libsonnet
  - >-
    https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html
priority: 3
ordinal: 66000
---

## Description

Actualmente `synapse.libsonnet` usa un init container con `envsubst` para inyectar secretos en `homeserver.yaml` y `registration.yaml` en tiempo de arranque (vía plantillas con `${VAR}`). Esto añade un init container, dos ConfigMaps de plantilla y la dependencia de la imagen `envsubst`.

El "engorro" viene de que inline-amos los secretos dentro del YAML. Synapse soporta leer la mayoría de secretos desde ficheros (`*_path`), lo que permite dejar el `homeserver.yaml` 100% estático y commiteado, montando los secretos como archivos (igual que ya se hace con `signing.key`). El objetivo es eliminar el init container y la dependencia de `envsubst`.

**Plan propuesto:**

`homeserver.yaml` → ConfigMap estático (sin ningún `${}`), usando:
- `macaroon_secret_key_path` (confirmado)
- `registration_shared_secret_path` (confirmado, desde Synapse 1.67)
- `form_secret_path` (verificar disponibilidad en la versión actual)
- oidc `client_secret_path` (verificar disponibilidad en la versión actual)
- Quitar `database.args.password` y pasar la contraseña vía env var `PGPASSWORD` (libpq la coge automáticamente)

`registration.yaml` (appservice) → el formato NO soporta `_path` para `as_token`/`hs_token` (son inline obligatoriamente). Como el fichero es pequeño, casi todo secreto y se comparte con mautrix-whatsapp, sellar el fichero completo como SealedSecret y montarlo directo en `/appservice/registration.yaml`.

**Resultado:** desaparece el init container y la dependencia de `envsubst` por completo.

**Trade-off:** se cambia 1 init container por varios ficheros de secreto sueltos (uno por entrada sellada). En líneas de código es un empate aproximado; lo que se gana es config estática, sin templating en runtime, y secretos inyectados de forma nativa.

**Pre-requisito de verificación:** confirmar contra la versión de Synapse en `versions.json` que existen `form_secret_path` y `client_secret_path` (los dos no verificados al 100%). Si alguno no existe en esa versión, mantener ese valor concreto vía un mecanismo alternativo o evaluar bump de versión.

Ficheros afectados: `lib/communications/synapse/synapse.libsonnet`, `synapse.homeserver.yaml`, `synapse.registration.yaml`, `synapse.secrets.json`.

## Implementation Plan

**Verificación previa (hecha):** las 4 opciones `*_path` existen en Synapse v1.162.0 (`versions.json`): `macaroon_secret_key_path` (1.121), `form_secret_path` (1.126), `registration_shared_secret_path` (1.67), oidc `client_secret_path` (1.91). No hace falta bump. `envsubst` NO se puede quitar de `versions.json` (lo usan authelia, facturascripts, immich, invidious, mautrix-whatsapp) → criterio #2 se cierra documentando que sigue en uso por otros.

**`client_id` de OIDC:** no existe `client_id_path` y el `client_id` no es secreto en OAuth2 (viaja en la URL del navegador) → se inlinea como valor público en el `homeserver.yaml` estático. Deja de estar sellado.

**Permisos:** el proceso Synapse corre como uid 991 (gosu-drop del entrypoint). Montajes read-only `root:0644` se leen igual que ya funciona `signing.key` hoy; `/media` (hostPath) ya es 991:991. No hace falta `securityContext` ni chown.

**Decisión tokens appservice (usuario): preservar.** Se leen AS/HS actuales del cluster a ficheros temporales (nunca a stdout), se renderiza el `registration.yaml` y se sella completo. mautrix-whatsapp queda intacto (sigue renderizando su copia vía envsubst desde el template compartido y usando el env-var `whatsapp-appservice-sealed-secret`, que Synapse sigue creando). Trade-off aceptado: los tokens quedan duplicados (env-var para mautrix + fichero sellado para Synapse) y el `registration.yaml` sellado es opaco en git.

**Cambios concretos:**
1. `synapse.homeserver.yaml` → estático, sin `${}`: `*_path` apuntando a `/secrets/<key>`, `client_id` inline, `database.args.password` eliminado.
2. `synapse.libsonnet` → sin init container; `/config` (ConfigMap estático), `/secrets` (SealedSecret `synapse-secrets` multi-clave), `/appservice/registration.yaml` (SealedSecret de fichero completo), `/keys` (sin cambios); env `PGPASSWORD` desde `synapse-db-sealed-secret`.
3. `synapse.registration.yaml` → sin cambios (sigue siendo el template compartido, fuente de verdad que lee mautrix y con el que se construye el fichero sellado).
4. `synapse.secrets.json` → re-sellado: `synapseSecrets` (4 claves para name `synapse-secrets`), `registrationFile` (fichero completo), se elimina el bloque `synapse` env-var y `OIDC_CLIENT_ID`; `signingKey` y `whatsappAppservice` sin cambios.

## Acceptance Criteria
- [ ] #1 El init container `config-init` con envsubst se elimina del deployment de Synapse
- [ ] #2 La dependencia de la imagen envsubst se retira de versions.json si no la usa ningún otro servicio
- [ ] #3 `homeserver.yaml` es un ConfigMap estático sin ninguna variable `${...}`; los secretos (macaroon, registration_shared, form, oidc client_secret) se inyectan vía opciones `*_path` montadas desde SealedSecret
- [ ] #4 La contraseña de Postgres se inyecta vía env var PGPASSWORD y se elimina `database.args.password` del YAML
- [ ] #5 `registration.yaml` se monta en /appservice/registration.yaml desde un SealedSecret de fichero completo (con as_token/hs_token incluidos), sin templating
- [ ] #6 Se verifica contra la versión de Synapse en versions.json que `form_secret_path` y `client_secret_path` están soportados antes de usarlos
- [ ] #7 Synapse arranca correctamente, conecta a Postgres, el login OIDC con Authelia funciona y el appservice de mautrix-whatsapp queda registrado
- [ ] #8 Se ejecuta `tk eval environments/communications` sin errores y el diff de manifiestos es coherente con el refactor
