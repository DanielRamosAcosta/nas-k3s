---
id: NASKS-64
title: Desplegar Synapse (Matrix homeserver)
status: In Progress
assignee: []
created_date: '2026-06-19'
updated_date: '2026-06-19'
labels:
  - app
  - system
dependencies: []
references:
  - 'https://github.com/element-hq/synapse'
  - 'https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html'
  - 'https://element-hq.github.io/synapse/latest/openid.html'
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Objetivo

Desplegar **Synapse** como homeserver Matrix en el cluster k3s. Elegido por su soporte nativo de Postgres, madurez, y compatibilidad garantizada con Mautrix-WhatsApp (NASKS-66). Autenticación SSO delegada a Authelia vía `oidc_providers`.

## Arquitectura

```
Cliente Matrix (Element, FluffyChat, etc.)
         │  SSO (m.login.sso)
         ▼
  synapse (homeserver)        ──OIDC──►  authelia.system
  matrix.danielramos.me                  auth.danielramos.me
         │
         │ Postgres
         ▼
  postgres.databases
  (DB lógica: matrix)
```

## Autenticación OIDC con Authelia

Synapse actúa como **relying party**: delega el login a Authelia vía `oidc_providers` en `homeserver.yaml`.

### Configuración en Authelia

```yaml
identity_providers:
  oidc:
    clients:
      - client_id: 'synapse'
        client_name: 'Synapse'
        client_secret: '<hash_generado_con_authelia_cli>'
        public: false
        redirect_uris:
          - "https://matrix.danielramos.me/_synapse/client/oidc/callback"
        scopes: ['openid', 'profile', 'email']
        grant_types: ['authorization_code']
        response_types: ['code']
        token_endpoint_auth_method: 'client_secret_post'
```

### Configuración en Synapse (`homeserver.yaml`)

```yaml
oidc_providers:
  - idp_id: authelia
    idp_name: "Authelia"
    discover: true
    issuer: "https://auth.danielramos.me"
    client_id: "synapse"
    client_secret: "<contraseña_en_texto_plano>"
    scopes: ["openid", "profile", "email"]
    user_mapping_provider:
      config:
        localpart_template: "{{ user.preferred_username }}"
        display_name_template: "{{ user.name }}"
        # usuario Authelia "dani" → Matrix ID: @dani:matrix.danielramos.me
```

## Componentes

### Synapse
- Imagen: `ghcr.io/element-hq/synapse`
- Namespace: `communications` (namespace nuevo, fase -1)
- Dominio: `matrix.danielramos.me`
- BBDD: Postgres compartido (`databases`), DB lógica `matrix`
- Configuración: `homeserver.yaml` vía ConfigMap; secretos en SealedSecret
- Media: hostPath `/cold-data/synapse/media` (puede crecer con el tiempo)
- Signing key: generada manualmente, sellada como SealedSecret y montada como fichero en `signing_key_path`; `data_directory` puede ser emptyDir (todo el estado persiste en Postgres)
- TLS vía Let's Encrypt + Traefik
- Registro: deshabilitado (`enable_registration: false`) — solo SSO via Authelia
- URL previews: deshabilitadas (`url_preview_enabled: false`)
- IngressRoute: sin middleware de Authelia — los clientes Matrix hablan directamente con Synapse
- Admin: solo `@dani:matrix.danielramos.me`; el bot del bridge no necesita admin global
- Resource limits: ninguno
- Métricas: habilitadas desde Fase 1 (`enable_metrics: true`, puerto 9090) para scrape de Prometheus

## Decisiones

- **Namespace**: `communications` (namespace nuevo, fase -1)
- **`server_name`**: `matrix.danielramos.me` — user IDs serán `@daniel:matrix.danielramos.me`; no requiere `.well-known` delegation
- **Federación**: deshabilitada — uso privado, principalmente para bridge WhatsApp
- **Element Web**: descartado por ahora — se valida con cliente de escritorio

## Notas

- `db_name` de Postgres no puede tener guiones (usar `matrix`)
- El hash del `client_secret` para Authelia se genera con `authelia crypto hash generate pbkdf2`
- `macaroon_secret_key`, `registration_shared_secret` y `form_secret` se generan manualmente (`openssl rand -hex 32`) antes del primer despliegue y se sellan como SealedSecret — nunca se deja que Synapse los genere, para que no cambien entre reinicios
- `app_service_config_files` se deja vacío en Fase 1; se añade y se reinicia Synapse cuando se despliegue el bridge en NASKS-66
<!-- SECTION:DESCRIPTION:END -->

## Fases de despliegue

### Fase -1 — Namespace

- [ ] #-1.1 Crear namespace `communications` en el cluster
- [ ] #-1.2 Añadir `communications` al namespace cheatsheet de CLAUDE.md

### Fase 0 — Base de datos

Dar de alta los recursos de Postgres antes de arrancar Tuwunel.

- [ ] #0.1 Crear DB lógica `matrix` en el Postgres compartido (`databases`)
- [ ] #0.2 Crear usuario `tuwunel` con permisos sobre `matrix`
- [ ] #0.3 Credenciales del usuario en SealedSecret (cluster-wide, para compartir con Tuwunel)

### Fase 1 — Despliegue mínimo sin OIDC

Objetivo: Synapse arrancando y accesible. Sin forma de hacer login — validación por logs y health check únicamente. `enable_registration: false` desde el primer momento.

- [ ] #1.1 `lib/communications/synapse/synapse.libsonnet` con StatefulSet, Service, IngressRoute
- [ ] #1.2 `homeserver.yaml` mínimo vía ConfigMap: `server_name`, Postgres, `enable_registration: false`
- [ ] #1.3 Generar secretos (`openssl rand -hex 32`) y sellar: `macaroon_secret_key`, `registration_shared_secret`, `form_secret`
- [ ] #1.4 Secretos de Postgres referenciados desde el SealedSecret cluster-wide de fase 0
- [ ] #1.5 hostPath `/cold-data/synapse/media` montado
- [ ] #1.6 TLS via Let's Encrypt + Traefik en `matrix.danielramos.me`
- [ ] #1.7 **Deploy y validar**: Synapse arranca sin errores en Loki, ArgoCD synced healthy, `/_matrix/client/versions` devuelve 200

### Fase 2 — OIDC con Authelia

Objetivo: login exclusivo via Authelia SSO; contraseña deshabilitada.

- [ ] #2.1 Generar `client_secret` y su hash (`authelia crypto hash generate pbkdf2`)
- [ ] #2.2 Registrar cliente `tuwunel` en la config de Authelia (`identity_providers.oidc.clients`)
- [ ] #2.3 Añadir `[[global.identity_provider]]` y `well_known.client` a `tuwunel.toml`
- [ ] #2.4 `client_secret` (texto plano) en SealedSecret strict de Tuwunel
- [ ] #2.5 `login_with_password = false`
- [ ] #2.6 **Deploy y validar** (login SSO funcional desde Element Web o FluffyChat)

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tuwunel corriendo y accesible en `https://matrix.danielramos.me`
- [ ] #2 DB `matrix` en Postgres compartido; Tuwunel arranca sin errores en Loki
- [ ] #3 Login con Authelia funcional desde un cliente Matrix
- [ ] #4 `login_with_password = false` — solo SSO activo
- [ ] #5 ArgoCD app synced healthy
<!-- AC:END -->
