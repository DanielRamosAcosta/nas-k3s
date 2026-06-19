---
id: NASKS-64
title: Desplegar Synapse (Matrix homeserver)
status: Done
assignee: []
created_date: '2026-06-19'
updated_date: '2026-06-19 20:08'
labels:
  - app
  - system
dependencies: []
references:
  - 'https://github.com/element-hq/synapse'
  - >-
    https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html
  - 'https://element-hq.github.io/synapse/latest/openid.html'
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## TLDR

Desplegar Synapse (homeserver Matrix) en `matrix.danielramos.me` con Postgres y SSO via Authelia. Servirá de base para el bridge Mautrix-WhatsApp (NASKS-66). Despliegue en tres fases: namespace → BBDD → Synapse básico → OIDC.

## Requisitos funcionales

- Homeserver Matrix accesible en `https://matrix.danielramos.me`
- Login exclusivo via Authelia SSO — sin contraseñas Matrix propias
- El primer login via Authelia crea la cuenta Matrix automáticamente
- User ID resultante: `@dani:matrix.danielramos.me`
- Preparado para conectar el bridge Mautrix-WhatsApp (NASKS-66)
- Sin federación — uso privado

## Plan técnico

**Homeserver:** Synapse (`ghcr.io/element-hq/synapse`) — elegido sobre alternativas por soporte nativo de Postgres y compatibilidad garantizada con bridges Mautrix.

**Arquitectura:**
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

**Decisiones técnicas:**
- Namespace: `communications` (nuevo)
- `server_name`: `matrix.danielramos.me` — no requiere `.well-known` delegation
- BBDD: Postgres compartido (`databases`), DB lógica `matrix`
- Media: hostPath `/cold-data/synapse/media`
- Signing key: generada manualmente y sellada como SealedSecret (montada como fichero); `data_directory` puede ser emptyDir
- Secretos Synapse (`macaroon_secret_key`, `registration_shared_secret`, `form_secret`): generados con `openssl rand -hex 32` y sellados — nunca generados por Synapse en arranque
- IngressRoute **sin** middleware de Authelia (los clientes Matrix hablan directamente con Synapse)
- Admin: solo `@dani:matrix.danielramos.me`
- Métricas: habilitadas desde Fase 1 (`enable_metrics: true`, puerto 9090)
- URL previews: deshabilitadas
- Sin resource limits
- Element Web: descartado por ahora
- `app_service_config_files`: vacío en Fase 1; se añade al desplegar el bridge en NASKS-66

**Configuración OIDC (Fase 2):**

En Authelia:
```yaml
identity_providers:
  oidc:
    clients:
      - client_id: 'synapse'
        client_name: 'Synapse'
        client_secret: '<hash $pbkdf2-...>'
        public: false
        redirect_uris:
          - "https://matrix.danielramos.me/_synapse/client/oidc/callback"
        scopes: ['openid', 'profile', 'email']
        grant_types: ['authorization_code']
        response_types: ['code']
        token_endpoint_auth_method: 'client_secret_post'
```

En `homeserver.yaml`:
```yaml
oidc_providers:
  - idp_id: authelia
    idp_name: "Authelia"
    discover: true
    issuer: "https://auth.danielramos.me"
    client_id: "synapse"
    client_secret: "<texto plano>"
    scopes: ["openid", "profile", "email"]
    user_mapping_provider:
      config:
        localpart_template: "{{ user.preferred_username }}"
        display_name_template: "{{ user.name }}"
```

> El `client_secret` en Authelia se genera con `authelia crypto hash generate pbkdf2`. Authelia almacena el hash; Synapse recibe el texto plano.
<!-- SECTION:DESCRIPTION:END -->

## Fase -1 — Namespace ✅

- [x] #-1.1 Crear `environments/communications/` y registrar en ArgoCD
- [x] #-1.2 Añadir `communications` al namespace cheatsheet de CLAUDE.md

## Fase 0 — Base de datos

- [ ] #0.1 Crear DB lógica `matrix` y usuario `synapse` en Postgres compartido (`databases`)
- [ ] #0.2 Credenciales en SealedSecret cluster-wide (compartido con Synapse desde namespace `communications`)
- [ ] #0.3 **Deploy y validar**: Job de creación de usuario completa sin errores

## Fase 1 — Synapse sin OIDC

Synapse arrancando y accesible. Sin login posible — validación solo por logs y health check.

- [ ] #1.1 `lib/communications/synapse/synapse.libsonnet`: StatefulSet, Service, IngressRoute
- [ ] #1.2 `homeserver.yaml` vía ConfigMap: `server_name`, Postgres, `enable_registration: false`, métricas, sin OIDC
- [ ] #1.3 Generar y sellar: `macaroon_secret_key`, `registration_shared_secret`, `form_secret`, signing key
- [ ] #1.4 Referenciar SealedSecret cluster-wide de Postgres
- [ ] #1.5 hostPath `/cold-data/synapse/media` montado
- [ ] #1.6 TLS via Let's Encrypt + Traefik en `matrix.danielramos.me`
- [ ] #1.7 **Deploy y validar**: sin errores en Loki, ArgoCD healthy, `/_matrix/client/versions` devuelve 200

## Fase 2 — OIDC con Authelia

Login exclusivo via Authelia SSO; primer login crea cuenta al vuelo.

- [ ] #2.1 Generar `client_secret` y hash (`authelia crypto hash generate pbkdf2`)
- [ ] #2.2 Registrar cliente `synapse` en config de Authelia
- [ ] #2.3 Añadir `oidc_providers` a `homeserver.yaml`
- [ ] #2.4 `client_secret` (texto plano) en SealedSecret strict de Synapse
- [ ] #2.5 **Deploy y validar**: login SSO funcional desde un cliente Matrix, cuenta `@dani:matrix.danielramos.me` creada al vuelo

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Synapse corriendo y accesible en `https://matrix.danielramos.me`
- [x] #2 DB `matrix` en Postgres compartido; Synapse arranca sin errores en Loki
- [x] #3 Login con Authelia funcional desde un cliente Matrix; cuenta creada al vuelo
- [x] #4 Sin login por contraseña — solo SSO activo
- [x] #5 ArgoCD app synced healthy
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-06-19 20:07
---
Fase 2 (OIDC) desplegada. Cliente `synapse` en Authelia (client_secret_basic, sin PKCE) + bloque `oidc_providers` en homeserver.yaml (issuer auth.danielramos.me, localpart=preferred_username). Credenciales selladas: client_id/secret plano en synapse-sealed-secret, client_id+hash pbkdf2 en authelia-sealed-secret. PRs #103 (OIDC) y #104 (fix listener type:http requerido, bug latente del refactor f25f3b5). Login SSO verificado end-to-end desde Element Classic en iOS: cuenta @dani:matrix.danielramos.me creada al vuelo, sync y device keys OK.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Synapse (homeserver Matrix) desplegado en matrix.danielramos.me con Postgres compartido y login exclusivo vía SSO de Authelia (OIDC).

**Resultado:**
- Homeserver accesible en https://matrix.danielramos.me, escuchando en :8008 (type: http) y métricas en :9090.
- Login solo por SSO (password_config.enabled: false). Cuenta creada al vuelo en el primer login: @dani:matrix.danielramos.me (localpart_template = preferred_username).
- Verificado end-to-end desde Element Classic en iOS: discovery OIDC 200, sync, device signing keys y pusher de notificaciones OK.

**OIDC (Fase 2):**
- Cliente `synapse` en Authelia: client_secret_basic, sin PKCE, redirect https://matrix.danielramos.me/_synapse/client/oidc/callback, scopes openid/profile/email, sin restricción de grupo (todos los usuarios Authelia).
- Bloque oidc_providers en homeserver.yaml: discover: true, issuer https://auth.danielramos.me, allow_existing_users, user_profile_method: userinfo_endpoint (workaround claims-hydration de la guía oficial).
- Credenciales selladas (kubeseal, scope strict): client_id + secret en texto plano en synapse-sealed-secret (inyectados vía envsubst); client_id + hash pbkdf2 en authelia-sealed-secret. Generadas con el CLI de Authelia, nunca expuestas en claro.

**PRs:** #103 (integración OIDC) y #104 (fix: restaurar type:http requerido en el listener de cliente — bug latente introducido por el refactor f25f3b5 que provocaba KeyError 'type' / CrashLoopBackOff al rolar la config).

Cliente iOS recomendado: Element Classic o FluffyChat (Element X NO es compatible: exige OIDC nativo vía MAS, no el SSO delegado m.login.sso). Base lista para el bridge Mautrix-WhatsApp (NASKS-66).
<!-- SECTION:FINAL_SUMMARY:END -->
