---
id: NASKS-73
title: Arreglar login OIDC de la CLI de ArgoCD (groups en id_token vía claims_policy)
status: To Do
assignee: []
created_date: '2026-06-26 15:18'
updated_date: '2026-06-26 15:28'
labels: []
dependencies: []
references:
  - 'https://www.authelia.com/integration/openid-connect/clients/argocd/'
  - 'https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/'
  - lib/system/argocd/argocd.libsonnet
  - lib/auth/authelia/authelia.config.yml
priority: medium
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

El login por SSO de la CLI de ArgoCD (`argocd login --sso`) falla con `invalid session: error while quering userinfo endpoint: no accessToken for <session>` hasta que el usuario hace login también en la UI web. Se debe a que ArgoCD obtiene los grupos vía el userinfo endpoint (necesita el `access_token` cacheado server-side) en lugar de leerlos del `id_token`. La solución es emitir el claim `groups` en el `id_token` mediante una `claims_policy` en Authelia (igual que ya se hace con Grafana) y dejar de usar `enableUserInfoGroups` en ArgoCD.

## 🎯 Contexto funcional

Hoy, para usar la CLI de ArgoCD hay que loguearse dos veces: primero en la CLI (que falla) y luego en la UI, y solo entonces la CLI empieza a funcionar. Es un comportamiento confuso y molesto que rompe el flujo de trabajo con la CLI (p. ej. `argocd app sync`). El objetivo es que `argocd login --sso` funcione directamente, sin depender de un login previo en la UI.

## ⚙️ Contexto técnico

Causa raíz confirmada contra la config del repo:

- En `lib/system/argocd/argocd.libsonnet` (`oidc.config` del `argocd-cm`) está configurado:
  - `enableUserInfoGroups: true`
  - `userInfoPath: '/api/oidc/userinfo'`
  Con esto ArgoCD NO lee los grupos del `id_token`, sino que llama al userinfo endpoint de Authelia, lo que requiere el `access_token` cacheado en el lado servidor.
- En `lib/auth/authelia/authelia.config.yml`, los dos clientes de ArgoCD (UI, ~línea 214; y CLI `ArgoCD CLI`, ~línea 282) NO tienen `claims_policy` asignada. Por defecto, Authelia (v4.38+) NO incluye `groups` en el `id_token` salvo que una `claims_policy` lo declare. Por eso ArgoCD se ve forzado a usar userinfo.
- El cliente CLI es público (`public: true`, `require_pkce: true`, `token_endpoint_auth_method: none`): el intercambio de código→tokens ocurre en el cliente (la máquina del usuario), por lo que el `argocd-server` nunca cachea el `access_token` de esa sesión → falla la llamada a userinfo con `no accessToken for <session>`. Al hacer login por la UI, el intercambio es server-side y el servidor sí cachea el `access_token`/grupos para el `sub`, por lo que después la CLI funciona.

Patrón de referencia ya presente en el repo: el cliente **Grafana** sí tiene `claims_policy: grafana` (definida en `authelia.config.yml`, líneas 74-76: `id_token: ['email', 'name', 'groups', 'preferred_username']`) y lee los grupos del `id_token`.

Cambios previstos:

1. Authelia (`lib/auth/authelia/authelia.config.yml`): añadir una `claims_policy` `argocd` con `id_token: ['email', 'groups']` (junto a las de grafana/sftpgo/booklore) y asignar `claims_policy: argocd` a AMBOS clientes de ArgoCD (UI y CLI).
2. ArgoCD (`lib/system/argocd/argocd.libsonnet`): eliminar `enableUserInfoGroups: true` y `userInfoPath` de `oidc.config` para que lea los grupos del `id_token`.
3. Desplegar vía GitOps (commit → rama manifests → sync en ArgoCD). Reloader reinicia Authelia y ArgoCD al cambiar sus ConfigMaps.
4. Verificar el RBAC por grupos de ArgoCD tras el cambio.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Los clientes OIDC de ArgoCD (UI y CLI) en Authelia emiten el claim `groups` en el `id_token` mediante una `claims_policy` dedicada (patrón equivalente al de Grafana)
- [ ] #2 La `oidc.config` de ArgoCD deja de usar `enableUserInfoGroups`/`userInfoPath` y obtiene los grupos del `id_token`
- [ ] #3 `argocd login --sso` desde la CLI funciona sin necesidad de login previo en la UI (desaparece el error `no accessToken for <session>`)
- [ ] #4 El RBAC por grupos de ArgoCD sigue funcionando correctamente tras el cambio (la autorización por grupos no se rompe)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Ciclos cortos: primero Authelia (añade `groups` al `id_token` sin romper nada, ya que ArgoCD sigue usando userinfo), se verifica, y solo entonces ArgoCD deja de usar userinfo. Este orden evita romper el RBAC: si se quitara `enableUserInfoGroups` antes de que Authelia emita `groups` en el `id_token`, ArgoCD se quedaría sin grupos y los `admins` perderían acceso.

> Nota de patrón: Grafana ya funciona exactamente así (lee `groups` del `id_token` vía `claims_policy: grafana`), por lo que el enfoque está validado en este mismo repo. NO hace falta `requestedIDTokenClaims` en la `oidc.config` de ArgoCD: la `claims_policy` de Authelia es la que fuerza que `groups` viaje en el `id_token`, y ArgoCD (sin `enableUserInfoGroups`) lo lee de ahí directamente.

## Fase 0 — Preparación

1. Pasar la tarea a `In Progress`.
2. Asegurar túnel SSH al clúster si hace falta: `ssh -fN -L 6443:localhost:6443 nas`.
3. Asegurar sesión válida de la CLI de ArgoCD (login UI + CLI como hasta ahora) para poder lanzar `argocd app sync`.
4. Crear rama de trabajo desde `main`.

## Fase 1 — Authelia: emitir `groups` en el `id_token`

Fichero: `lib/auth/authelia/authelia.config.yml`

1. En la sección `claims_policies` (junto a `grafana`, `sftpgo`, `booklore`, ~líneas 74-87), añadir SOLO los claims que ArgoCD solicita por scope (`email`, `groups`; ArgoCD no pide el scope `profile`, por lo que `name`/`preferred_username` no aplican — a diferencia de Grafana, que sí pide `profile`):
   ```yaml
   argocd:
     id_token: ['email', 'groups']
   ```
2. Asignar `claims_policy: argocd` al cliente **ArgoCD** (UI, bloque ~líneas 214-236, debajo de `authorization_policy: two_factor`, igual que Grafana tiene `claims_policy: grafana`).
3. Asignar `claims_policy: argocd` al cliente **ArgoCD CLI** (bloque ~líneas 282-302, debajo de `authorization_policy: two_factor`).

Validación local:
- `tk eval environments/auth >/dev/null` — confirma SOLO que el Jsonnet compila y que el `importstr` del YAML no rompe. NO valida la sintaxis YAML interna de Authelia (un typo de indentación/claim pasaría esta comprobación). La validación YAML real ocurre al arrancar Authelia → se comprueba en los logs tras el despliegue.

Despliegue (GitOps):
1. Commit + push de la rama, abrir PR y mergear a `main` (o push directo según el flujo habitual del repo).
2. Esperar a que CI exporte a la rama `manifests`.
3. `argocd app sync authelia --grpc-web`.
4. Reloader reinicia el pod de Authelia al cambiar su ConfigMap.

Verificación Fase 1:
- Logs de arranque de Authelia vía MCP `grafanaSelfHosted` → `query_loki_logs` (datasource Loki uid `P8E80F9AEF21F6940`), últimos ~10 min, con selector: `{namespace="auth", pod=~"authelia.*"} |~ "(?i)error|fatal|invalid|configuration"`. Confirmar que Authelia arranca SIN errores de validación de config (una `claims_policy` mal escrita impediría el arranque). Opcional: confirmar el reinicio en `{namespace="kube-system", pod=~"reloader.*"}` ("Changes detected ... updated 'authelia'").
- El login en la UI de ArgoCD sigue funcionando con normalidad (no se ha roto nada). En este punto `groups` está disponible tanto en el `id_token` como en userinfo; ArgoCD sigue usando userinfo, así que el comportamiento no cambia aún.

## Fase 2 — ArgoCD: leer `groups` del `id_token` (quitar userinfo)

Fichero: `lib/system/argocd/argocd.libsonnet` (`oidc.config`, líneas 28-37)

1. Eliminar las claves `enableUserInfoGroups: true` y `userInfoPath: '/api/oidc/userinfo'` del objeto `oidc.config`. Queda:
   ```jsonnet
   'oidc.config': std.manifestYamlDoc({
     name: 'Authelia',
     issuer: 'https://auth.danielramos.me',
     clientID: '$argocd-oidc-secret:client-id',
     clientSecret: '$argocd-oidc-secret:client-secret',
     cliClientID: '$argocd-oidc-secret:cli-client-id',
     requestedScopes: ['openid', 'email', 'groups', 'offline_access'],
   }),
   ```

Validación local:
- `tk eval environments/argocd | jq -r '..|select(.kind?=="ConfigMap" and .metadata.name=="argocd-cm")|.data["oidc.config"]'` debe mostrar el YAML SIN `enableUserInfoGroups` ni `userInfoPath` (y conservando `requestedScopes`).

Despliegue (GitOps):
1. Commit + push + merge a `main`.
2. Esperar export a `manifests`.
3. `argocd app sync argocd --grpc-web`.
4. Reloader reinicia el `argocd-server` al cambiar `argocd-cm` (esto además limpia la caché en memoria de access tokens/userinfo del flujo anterior).

Verificación Fase 2 (el fix):
- Cerrar sesión local de la CLI para partir de cero: `argocd logout argocd.danielramos.me`.
- (Para probar el caso real que motivó la tarea) cerrar también la sesión de la UI en el navegador, de modo que el server no tenga ningún access token cacheado por la UI.
- `argocd login argocd.danielramos.me --grpc-web --sso` — debe completarse y dejar la sesión operativa SIN necesidad de login previo en la UI (ya NO aparece `no accessToken for <session>`). → AC #3
- `argocd account get-user-info --grpc-web` — la salida debe incluir un campo `groups` con los grupos del usuario (debe aparecer `admins`). Si `groups` sale vacío/null, el `id_token` no trae los grupos → revisar la `claims_policy` de la Fase 1.
- `argocd app list --grpc-web` — debe listar TODAS las Applications. Lista no vacía y sin error de permisos confirma que el RBAC `g, admins, role:admin` (con `scopes: '[groups]'`) sigue concediendo acceso admin. → AC #4

## Fase 3 — Cierre

1. Verificar los 4 criterios de aceptación.
2. Confirmar con el usuario y, tras su OK explícito, marcar AC/DoD y `status: Done` + commit final.

## Rollback

Si tras la Fase 2 el RBAC se rompe (p. ej. `get-user-info` no muestra grupos o `app list` da permission denied), revertir el commit de la Fase 2 (restaurar `enableUserInfoGroups`/`userInfoPath`), `argocd app sync argocd --grpc-web`, y volver al comportamiento actual (login UI + CLI) mientras se investiga. La Fase 1 (claims_policy en Authelia) es aditiva y no necesita revertirse.
<!-- SECTION:PLAN:END -->
