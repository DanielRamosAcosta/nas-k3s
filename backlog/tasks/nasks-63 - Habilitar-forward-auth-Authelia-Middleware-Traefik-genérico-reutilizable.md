---
id: NASKS-63
title: Habilitar forward-auth Authelia + Middleware Traefik genérico reutilizable
status: To Do
assignee: []
created_date: '2026-05-08 06:55'
updated_date: '2026-05-08 07:26'
labels:
  - auth
  - infra
  - system
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Objetivo

Habilitar el flujo **forward-auth de Authelia** (vía Traefik) como pieza reutilizable de infra, para apps que NO tienen OIDC nativo. Hoy en el cluster TODAS las apps integradas con Authelia usan OIDC nativo del propio servicio (Immich, Grafana, Jellyfin, Booklore, SFTPGo, ArgoCD, FacturaScripts). No existe ningún `Middleware` CR de Traefik tipo `forwardAuth` ni precedente de uso.

## Motivación

Bloqueante para la **fase 3 de NASKS-61 (wger)** — wger no soporta OIDC, OAuth, SAML ni LDAP nativamente, solo `AUTH_PROXY` por headers HTTP. Sin forward-auth no hay SSO.

La pieza se diseña como genérica para que futuras apps sin OIDC nativo (paperless, vaultwarden si se decidiera, etc.) la puedan reutilizar añadiendo el middleware al IngressRoute.

## Decisiones cerradas

| # | Decisión | Valor |
|---|---|---|
| 1 | `allowCrossNamespace` en Traefik | **Activar** en `lib/system/traefik/traefik.libsonnet` (Helm values). Patrón estándar Traefik multi-namespace. Sin esto, las IngressRoute de otros namespaces que referencien el middleware en `auth` caen silenciosamente. |
| 2 | `default_policy` Authelia | **Mantener `two_factor` global** — ya es lo que aplica OIDC. Sin reglas por host, todos los consumidores forward-auth heredan 2FA. Aceptable como contrato simple. |
| 3 | API del helper jsonnet | **(a) `lib/utils/middleware.libsonnet`** con `autheliaForwardAuth()`. Uso: `u.middleware.autheliaForwardAuth()`. Encaja con el patrón `lib/utils/` (sealedSecret, ingressRoute...) y deja sitio para futuros middlewares (rate limit, geo-block). |
| 4 | Layout del Middleware CR | **Definirlo como componente de `lib/auth/authelia/authelia.libsonnet`** (precedente: immich define Middleware in-line). Namespace del CR: `auth`. |

## Alcance

### 1. Authelia (verificación)
- Confirmar que `/api/authz/forward-auth` está expuesto. Authelia 4.39+ lo expone por defecto cuando `access_control` está definido (lo está, ver `lib/auth/authelia/authelia.config.yml:22-26`). No requiere cambios de config.

### 2. Middleware CR de Traefik
- Añadir al módulo `lib/auth/authelia/authelia.libsonnet` un nuevo componente:
  ```jsonnet
  forwardAuthMiddleware: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'authelia-forwardauth', namespace: 'auth' },
    spec: {
      forwardAuth: {
        address: 'http://authelia.auth.svc.cluster.local:9091/api/authz/forward-auth',
        trustForwardHeader: true,
        authResponseHeaders: ['Remote-User', 'Remote-Email', 'Remote-Name', 'Remote-Groups'],
      },
    },
  },
  ```

### 3. `allowCrossNamespace` en Traefik
- Editar `lib/system/traefik/traefik.libsonnet` (Helm values, ~línea 137):
  ```jsonnet
  providers: {
    kubernetesCRD: {
      enabled: true,
      allowCrossNamespace: true,  // NUEVO
      allowEmptyServices: true,
    },
  },
  ```
- Esto permite que `IngressRoute` en cualquier namespace referencie `Middleware` en otro.

### 4. Helper `lib/utils/middleware.libsonnet`
- Crear archivo nuevo:
  ```jsonnet
  {
    autheliaForwardAuth():: { name: 'authelia-forwardauth', namespace: 'auth' },
  }
  ```
- Registrar en `lib/utils.libsonnet` (línea ~16-43): añadir `middleware: import 'utils/middleware.libsonnet'`.

### 5. Documentación
- Añadir sección en CLAUDE.md (en el bloque de "Networking & Auth") explicando:
  - Apps con OIDC nativo → integrar directo con Authelia OIDC.
  - Apps sin OIDC → middleware forward-auth, configurar la app para leer `Remote-User`/`Remote-Email`/`Remote-Name`.
  - Heredan `two_factor` (default policy de Authelia).

## Validación

1. Aplicar cambios → ArgoCD sync de `auth` y `system` (Traefik) healthy.
2. Verificar Middleware CR:
   ```bash
   kubectl get middleware -n auth authelia-forwardauth
   ```
3. Verificar `allowCrossNamespace` en Traefik:
   ```bash
   kubectl get deploy -n system traefik -o yaml | grep -i crossnamespace
   ```
4. Validación end-to-end: usar wger (NASKS-61 fase 3) como primer consumidor. Aplicar middleware a su IngressRoute, acceder a `gym.danielramos.me`, verificar redirección a Authelia y que tras login los headers `Remote-*` llegan al pod (verificable en logs de wger durante primer login).

## Fuera de alcance

- Migrar apps que YA usan OIDC nativo a forward-auth.
- Reglas `access_control` por host (queda con `default_policy: two_factor`).
- Multi-domain forward-auth.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Middleware Traefik `authelia-forwardauth` desplegado en namespace `auth` (definido como componente de `authelia.libsonnet`)
- [ ] #2 `allowCrossNamespace: true` activado en `lib/system/traefik/traefik.libsonnet` y aplicado en el cluster
- [ ] #3 Helper jsonnet `u.middleware.autheliaForwardAuth()` disponible en `lib/utils/middleware.libsonnet` y registrado en `lib/utils.libsonnet`
- [ ] #4 Headers `Remote-User`, `Remote-Email`, `Remote-Name`, `Remote-Groups` llegan al pod consumidor tras forward-auth
- [ ] #5 Documentación añadida en CLAUDE.md sección Networking & Auth: cuándo OIDC vs forward-auth, cómo aplicar, hereda `two_factor`
- [ ] #6 Validado end-to-end con wger (fase 3 de NASKS-61) como primer consumidor
<!-- AC:END -->
