---
id: NASKS-68
title: >-
  Refactorizar config de Synapse: eliminar envsubst usando secretos nativos por
  path
status: To Do
assignee: []
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
priority: low
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 El init container `config-init` con envsubst se elimina del deployment de Synapse
- [ ] #2 La dependencia de la imagen envsubst se retira de versions.json si no la usa ningún otro servicio
- [ ] #3 `homeserver.yaml` es un ConfigMap estático sin ninguna variable `${...}`; los secretos (macaroon, registration_shared, form, oidc client_secret) se inyectan vía opciones `*_path` montadas desde SealedSecret
- [ ] #4 La contraseña de Postgres se inyecta vía env var PGPASSWORD y se elimina `database.args.password` del YAML
- [ ] #5 `registration.yaml` se monta en /appservice/registration.yaml desde un SealedSecret de fichero completo (con as_token/hs_token incluidos), sin templating
- [ ] #6 Se verifica contra la versión de Synapse en versions.json que `form_secret_path` y `client_secret_path` están soportados antes de usarlos
- [ ] #7 Synapse arranca correctamente, conecta a Postgres, el login OIDC con Authelia funciona y el appservice de mautrix-whatsapp queda registrado
- [ ] #8 Se ejecuta `tk eval environments/communications` sin errores y el diff de manifiestos es coherente con el refactor
<!-- AC:END -->
