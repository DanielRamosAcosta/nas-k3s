---
title: "Migrar auth de wger a OIDC nativo (django-allauth)"
status: In Progress
priority: 3
labels: [wger, oidc, authelia, business]
parent:
references:
  - "https://github.com/wger-project/wger/issues/1797"
  - "https://wger.readthedocs.io/en/latest/administration/social_auth.html#generic-openid-connect-oidc"
created_date: 2026-10-12 21:42
---

## Description

## 📌 TLDR

wger ya soporta OIDC nativo (vía `django-allauth`, issue #1797 cerrado). Sustituir el actual forward-auth de Authelia + auth-proxy headers por un login OIDC "de verdad" (botón "login con Authelia"), registrando a wger como cliente OIDC en Authelia.

## 🎯 Contexto funcional

Hoy wger se autentica con el middleware `authelia-forwardauth` de Traefik + confianza en headers de proxy (`Remote-User`, etc.), creando el usuario de forma transparente. Funciona, pero es un truco: la cadena es wger ← Traefik ← Authelia y wger confía ciegamente en los headers. OIDC nativo simplifica la cadena a wger ↔ Authelia, es más robusto (especialmente si algún día se usa la app móvil o se expone la API con SSO) y alinea wger con el resto de servicios OIDC del homelab (immich, grafana, seerr, etc.).

## ⚙️ Contexto técnico

### Estado actual (lo que hay que sustituir)
- `lib/business/wger/wger.libsonnet:142-151` — IngressRoute con `middlewares=[u.middleware.autheliaForwardAuth()]` en la ruta raíz; segunda ruta `PathPrefix(/api)` **sin** middleware.
- ConfigMap de env de wger con las auth-proxy vars:
  - `AUTH_PROXY_HEADER: 'HTTP_REMOTE_USER'`
  - `AUTH_PROXY_USER_EMAIL_HEADER: 'HTTP_REMOTE_EMAIL'`
  - `AUTH_PROXY_USER_NAME_HEADER: 'HTTP_REMOTE_NAME'`
  - `AUTH_PROXY_TRUSTED_IPS: '127.0.0.1,10.42.0.0/16'`
  - `AUTH_PROXY_CREATE_UNKNOWN_USER: 'True'`
- Middleware forward-auth: `lib/auth/authelia/authelia.libsonnet:72-83` → `http://authelia.auth.svc.cluster.local:9091/api/authz/forward-auth`.
- **No** existe cliente OIDC de wger en `authelia.config.yml` (sí los hay para immich, grafana, jellyfin, argocd, seerr, synapse, facturascripts…).

### Cómo se mete OIDC en wger (según la doc oficial)
wger usa **`django-allauth`** con el proveedor genérico `openid_connect`. Dos piezas:

**1. Habilitar el proveedor por env var** (en el ConfigMap de env de wger):
```
WGER_SOCIAL_PROVIDERS=openid_connect
```

**2. Registrar el proveedor como fila en la BD** (`SocialApp` de allauth). No es por env var — es un registro en Postgres. Vía `./manage.py shell`:
```python
from allauth.socialaccount.models import SocialApp
from django.contrib.sites.models import Site

app = SocialApp.objects.create(
    provider='openid_connect',
    provider_id='authelia',                 # usado en la URL de callback
    name='Authelia',
    client_id='wger',
    secret='<client_secret>',               # del SealedSecret, nunca en claro en git
    settings={'server_url': 'https://auth.danielramos.me'},  # acepta base o .well-known/openid-configuration
)
app.sites.add(Site.objects.get(id=1))
```
- **Callback a registrar en Authelia**: `https://gym.danielramos.me/accounts/oidc/authelia/login/callback/` (prefijo `accounts` **plural** — es el default de allauth, configurable con `SOCIALACCOUNT_OPENID_CONNECT_URL_PREFIX`; debe coincidir carácter a carácter, barra final incluida)
- Para varios IdPs: múltiples `SocialApp`, cada uno con su `provider_id`.

### Punto delicado: el `SocialApp` vive en la BD (fuera de git)
Esto rompe el patrón declarativo del repo (todo lo demás vive en Jsonnet/ConfigMap/SealedSecret). Opciones para provisionarlo de forma reproducible:
- **(A, recomendada) Job/initContainer idempotente** que ejecute el snippet de `manage.py shell` con `update_or_create` (no `create`) leyendo `client_id`/`secret` de env (desde el SealedSecret) — así el registro se regenera solo si se borra la BD o se reinstala el NAS, igual que otros estados no-git documentados en CLAUDE.md.
- (B) Documentar un one-shot manual en el runbook (`docs/nas-k3s/Docs/`) y asumir que al recrear la BD hay que rehacerlo. Más simple pero frágil.

### Cliente OIDC en Authelia
- Añadir cliente `wger` en `authelia.config.yml` (`redirect_uris: [https://gym.danielramos.me/accounts/oidc/authelia/login/callback/]`, scopes `openid profile email` — wger no usa grupos para roles, flujo authorization_code + secret según convención del repo).
- `client_id` legible (`wger`), no sellado — ver [[oidc-client-id-not-secret-readable]].
- `client_secret` en SealedSecret (hash en Authelia + valor plano consumido por el Job/ConfigMap de wger).
- Apoyarse en la skill `integrate-new-oidc-service` para el patrón exacto del repo.

### Decisión sobre el forward-auth actual
- Al pasar a OIDC, la ruta raíz **no** debe llevar `authelia-forwardauth` (bloquearía el callback OIDC) — IngressRoute plano estilo seerr/jellyfin. Confirmar que quitar el forward-auth no deja la instancia abierta (wger exige login propio por defecto; OIDC pasa a ser el método de login).
- Retirar las `AUTH_PROXY_*` del ConfigMap.
- Mantener `/api` sin auth si se quiere seguir usando tokens propios de wger.

## Acceptance Criteria

- [ ] #1 wger ofrece login OIDC contra Authelia (botón/flujo "login con Authelia") y crea/mapea el usuario correctamente
- [ ] #2 Cliente OIDC `wger` registrado en `authelia.config.yml` con su SealedSecret de `client_secret`
- [ ] #3 El `SocialApp` de allauth se provisiona de forma reproducible (Job idempotente documentado), no por un paso manual que se olvide al recrear la BD
- [ ] #4 Retirado el forward-auth + auth-proxy headers del IngressRoute/ConfigMap (o decisión consciente y documentada de mantenerlos)
- [ ] #5 Preservado el acceso sin auth a `/api` para apps/tokens propios de wger

## Implementation Plan

Ejecución secuencial fase a fase: implementar **una** fase, **parar**, **desplegar** y **verificar su checkpoint** antes de pasar a la siguiente. Authelia **no tiene** guía oficial de OIDC para wger (verificado); se usa el patrón genérico del repo (skill `integrate-new-oidc-service`) + la doc de `django-allauth`.

Issuer de Authelia: `https://auth.danielramos.me`. Dominio de wger: `gym.danielramos.me`.

### Fase 1 — Registrar el cliente OIDC `wger` en Authelia

Objetivo: dar de alta el cliente en Authelia **sin tocar wger todavía**. No cambia nada de cara al usuario; es seguro.

1. **Generar credenciales** siguiendo la skill `integrate-new-oidc-service` (pasos 4-5), con el pod de Authelia, sin exponer valores en el contexto:
   ```bash
   kubectl exec -n auth deploy/authelia -- authelia crypto rand --length 72 --charset rfc3986 \
     | tail -1 | sed 's/.*: //' | tr -d '\n' > /tmp/oidc_client_id.txt
   kubectl exec -n auth deploy/authelia -- authelia crypto rand --length 72 --charset rfc3986 \
     | tail -1 | sed 's/.*: //' | tr -d '\n' > /tmp/oidc_secret_plain.txt
   kubectl exec -i -n auth deploy/authelia -- \
     authelia crypto hash generate pbkdf2 --variant sha512 --no-confirm \
     --password "$(cat /tmp/oidc_secret_plain.txt)" \
     | grep -i 'digest' | sed -E 's/^Digest:[[:space:]]*//' | tr -d '\n' > /tmp/oidc_secret_hash.txt
   ```
   Nota: `client_id` aleatorio de 72 chars (no slug legible) para seguir el patrón mayoritario del fichero; alternativamente `client_id: 'wger'` legible como synapse/seerr — ver [[oidc-client-id-not-secret-readable]]. Decidir antes de generar; si se opta por slug legible, no hace falta el fichero `oidc_client_id.txt` ni meterlo en SealedSecrets.
2. **Añadir el bloque del cliente** en `lib/auth/authelia/authelia.config.yml` (al final de la lista de `clients`), copiando el patrón de un cliente `client_secret_post` existente (p. ej. Immich):
   ```yaml
   - client_id: '{{ env `IDENTITY_PROVIDERS_OIDC_CLIENTS_WGER_CLIENT_ID` }}'
     client_name: wger
     client_secret: '{{ env `IDENTITY_PROVIDERS_OIDC_CLIENTS_WGER_CLIENT_SECRET_DIGEST` }}'
     public: false
     authorization_policy: two_factor
     consent_mode: implicit
     require_pkce: false
     redirect_uris:
       - 'https://gym.danielramos.me/accounts/oidc/authelia/login/callback/'
     scopes:
       - openid
       - profile
       - email
     response_types:
       - code
     grant_types:
       - authorization_code
     access_token_signed_response_alg: none
     userinfo_signed_response_alg: none
     token_endpoint_auth_method: client_secret_post
   ```
   - `provider_id` = `authelia` → el callback de allauth es `/accounts/oidc/authelia/login/callback/` (prefijo `accounts` **plural**, confirmado en la doc de allauth). Debe coincidir **carácter a carácter** (barra final incluida) o Authelia rechaza con `invalid redirect_uri`. Si wger hubiera personalizado `SOCIALACCOUNT_OPENID_CONNECT_URL_PREFIX`, ajustar; por defecto es `oidc`.
   - `consent_mode: implicit` — convención del repo (todos los clientes existentes lo usan), evita pantalla de consentimiento repetida.
   - `token_endpoint_auth_method: client_secret_post` — allauth (OAuth2Client genérico) manda las credenciales en el body del POST. Confirmar en el primer login; si falla con 401 en el token endpoint, probar `client_secret_basic`.
3. **Cifrar y meter en los SealedSecrets** (skill, pasos 7a-7c). `client_id` + hash al SealedSecret de Authelia (`authelia-sealed-secret`, ns `auth`); `client_id` + secret en texto plano al SealedSecret de wger (`wger-sealed-secret`, ns `business`) bajo claves `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET`:
   ```bash
   tr -d '\n' < /tmp/oidc_client_id.txt   | ./scripts/encrypt-secret.sh auth authelia-sealed-secret > /tmp/sealed_auth_cid.txt
   tr -d '\n' < /tmp/oidc_secret_hash.txt | ./scripts/encrypt-secret.sh auth authelia-sealed-secret > /tmp/sealed_auth_hash.txt
   tr -d '\n' < /tmp/oidc_client_id.txt   | ./scripts/encrypt-secret.sh business wger-sealed-secret > /tmp/sealed_wger_cid.txt
   tr -d '\n' < /tmp/oidc_secret_plain.txt| ./scripts/encrypt-secret.sh business wger-sealed-secret > /tmp/sealed_wger_csec.txt
   ```
   Inyectar con `jq --rawfile` (ver skill 7c) en `lib/auth/authelia/authelia.secrets.json` (claves `IDENTITY_PROVIDERS_OIDC_CLIENTS_WGER_CLIENT_ID` / `_CLIENT_SECRET_DIGEST`) y en `lib/business/wger/wger.secrets.json` (claves `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` bajo `.wger`). Comprobar que el SealedSecret de Authelia carga esas env vars (patrón `{{ env ... }}` del resto de clientes).
4. **Verificar render** sin exponer secretos:
   ```bash
   tk eval environments/auth >/dev/null && echo "eval auth OK"
   tk eval environments/business >/dev/null && echo "eval business OK"
   tk eval environments/auth | jq -r '.. | objects | select(.kind=="SealedSecret" and .metadata.name=="authelia-sealed-secret") | .spec.encryptedData | keys[] | select(test("WGER"))'
   ```
5. **Limpiar temporales** (skill paso 8): `rm -f /tmp/oidc_*.txt /tmp/sealed_*.txt`.
6. **Desplegar** con la skill `/deploy` (solo el cambio de Authelia + el SealedSecret de wger; wger aún no usa OIDC).

   **Checkpoint Fase 1:** Authelia arranca sin errores de config (`{namespace="auth", pod=~"authelia.*"}` en Loki, sin `error parsing` ni `client ... invalid`). El cliente `wger` aparece en el discovery/registro de clientes. wger sigue funcionando igual que antes (forward-auth intacto).

### Fase 2 — Habilitar el proveedor OIDC en wger (manteniendo forward-auth)

Objetivo: activar allauth OIDC y provisionar el `SocialApp` de forma reproducible, **sin** quitar aún el forward-auth (red de seguridad). Verificable de forma aislada.

1. En `lib/business/wger/wger.libsonnet`, añadir al `configEnv` (ConfigMap de entorno):
   ```jsonnet
   WGER_SOCIAL_PROVIDERS: 'openid_connect',
   ```
2. **Provisionar el `SocialApp` (fila en Postgres) de forma idempotente.** El `SocialApp` vive en la BD, no en env (ver ⚙️ Contexto técnico). Opción elegida: **Job de ArgoCD con hook `PostSync`** (no initContainer). Un PostSync corre **después** de que el pod principal de wger esté listo y haya aplicado sus migraciones (`DJANGO_PERFORM_MIGRATIONS: 'True'`), evitando el acoplamiento de orden migrate↔provision (un initContainer correría ANTES del `migrate` y podría toparse con una migración de allauth pendiente → esquema viejo). ArgoCD re-ejecuta el hook en cada sync, así que sigue siendo reproducible (cumple AC #3).
   ```jsonnet
   // Job 'wger-provision-oidc' en el módulo, con:
   //   metadata.annotations:
   //     'argocd.argoproj.io/hook': 'PostSync'
   //     'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation'
   //   spec.template.spec.containers[0]:
   //     image: u.image(versions.wger.image, versions.wger.version)
   //     workingDir: <dir del proyecto wger>   // en vez de ruta absoluta a manage.py
   //     command: ['python3', 'manage.py', 'shell', '-c', <<snippet>>]
   //     env: commonEnv(this)  (trae DJANGO_DB_* + OIDC_CLIENT_ID/SECRET)
   //   restartPolicy: OnFailure
   ```
   Snippet Python (idempotente, keyed en provider+provider_id):
   ```python
   import os
   from allauth.socialaccount.models import SocialApp
   from django.contrib.sites.models import Site
   app, _ = SocialApp.objects.update_or_create(
       provider='openid_connect', provider_id='authelia',
       defaults=dict(name='Authelia',
                     client_id=os.environ['OIDC_CLIENT_ID'],
                     secret=os.environ['OIDC_CLIENT_SECRET'],
                     settings={'server_url': 'https://auth.danielramos.me'}))
   app.sites.add(Site.objects.get(id=1))
   ```
   - **Verificar antes de fijar el `command`:** el binario es `python3` (no `python`), el `workingDir` correcto del proyecto wger (invocar `manage.py` relativo evita depender de una ruta absoluta incierta — la doc de wger siempre lo invoca relativo al WORKDIR), y que la columna `settings` (JSON) existe en la versión de allauth que trae la imagen (`wger/server` pinada en `lib/versions.json`).
   - `update_or_create` (keyed en provider+provider_id) y `sites.add` son idempotentes; `Site.objects.get(id=1)` ya tiene el dominio correcto vía `SITE_URL`.
   - **Verificar que el Job queda bajo la Application `wger` existente (no crea una app nueva):** al devolverse como un campo más de `wger.new()`, `u.Environment`/`labelApp` le estampa `labels.app: wger` por recursión. Confirmar con `tk eval environments/business | jq '.. | objects | select(.kind=="Job" and .metadata.name=="wger-provision-oidc") | {labels: .metadata.labels, ann: .metadata.annotations}'` que lleva `app: wger` + las dos annotations de hook. Al ser un hook de ArgoCD queda fuera del tracking/prune normal (lo gestiona `hook-delete-policy`), así que no debe quedar huérfano ni generar una Application aparte.
3. **Desplegar** con la skill `/deploy`.

   **Checkpoint Fase 2:** el Job `wger-provision-oidc` (PostSync) termina `Completed` sin traceback (logs en Loki `{namespace="business", pod=~"wger-provision-oidc.*"}`). El pod de wger queda `Running`. La fila `SocialApp` existe (verificable con `kubectl exec deploy/wger -- python3 manage.py shell -c "from allauth.socialaccount.models import SocialApp; print(list(SocialApp.objects.values_list('provider_id','name')))"`). wger sigue protegido por forward-auth (acceso sin cambios).

### Fase 3 — Quitar el forward-auth y pasar a login OIDC puro

Objetivo: retirar el middleware de Authelia y los auth-proxy headers; dejar que el login lo gestione wger vía OIDC. Última fase, cambio visible.

1. **Red de seguridad antes de quitar el proxy:** confirmar que existe un acceso alternativo por si OIDC falla — un superusuario local de Django (`kubectl exec deploy/wger -- python3 manage.py createsuperuser` si no existe) con el que entrar por `/django-admin/` aunque OIDC esté roto. Esto evita quedarse fuera.
2. En `lib/business/wger/wger.libsonnet`:
   - **IngressRoute plano** (estilo seerr/jellyfin): quitar `middlewares=[u.middleware.autheliaForwardAuth()]`. Replantear los `extraRoutes`: con el forward-auth fuera, la ruta raíz ya no lleva middleware, así que la separación `/api` deja de ser necesaria para el bypass de auth. Revisar si se puede simplificar a `u.ingressRoute.from(self.service, 'gym.danielramos.me')` a secas (AC #5: `/api` queda igualmente accesible, ya que ninguna ruta lleva auth de Traefik).
   - Quitar del `configEnv` las vars `AUTH_PROXY_HEADER`, `AUTH_PROXY_USER_EMAIL_HEADER`, `AUTH_PROXY_USER_NAME_HEADER`, `AUTH_PROXY_TRUSTED_IPS`, `AUTH_PROXY_CREATE_UNKNOWN_USER`.
3. **Mapeo de usuarios (hacer ANTES de quitar el proxy — riesgo alto de duplicado/pérdida de historial):** con los auth-proxy headers fuera, allauth **no** reutiliza automáticamente la cuenta creada por el proxy salvo que enlace por email. Pasos:
   - Inspeccionar qué usuario(s) creó el proxy: `kubectl exec deploy/wger -- python3 manage.py shell -c "from django.contrib.auth import get_user_model; print([(u.username,u.email) for u in get_user_model().objects.all()])"`.
   - Comparar con lo que entrega Authelia: `preferred_username` (→ username que usará allauth) y `email`. Si el `username` del proxy (`Remote-User`) difiere del `preferred_username` de Authelia, o el email no coincide, el primer login OIDC **creará una cuenta nueva** y el historial de entrenamientos quedará huérfano.
   - Mitigación: asegurar que el email de la cuenta existente coincide con el de Authelia y confiar en el enlace por email de allauth (`ACCOUNT_UNIQUE_EMAIL`/`SOCIALACCOUNT_EMAIL_AUTHENTICATION`, si wger los expone); o, si no, renombrar/mergear la cuenta existente a mano **antes** del primer login OIDC. wger no expone fácilmente esos settings por env — comprobar qué permite la imagen.
   - Como el homelab tiene pocos usuarios, lo pragmático puede ser: anotar username/email actuales, y tras el primer login OIDC reasignar el historial al nuevo usuario si allauth duplicó.
4. **Desplegar** con la skill `/deploy`.

   **Checkpoint Fase 3 (AC #1):** entrar en `https://gym.danielramos.me` ya **no** dispara el portal forward-auth de Authelia de golpe; aparece la pantalla de login de wger con el botón "Authelia". El flujo OIDC completo funciona (login → callback `/accounts/oidc/authelia/login/callback/` → sesión iniciada en wger como el usuario correcto). `/api` sigue accesible sin auth de Traefik (AC #5). El superusuario local sigue entrando por `/django-admin/` (red de seguridad). Logs de wger y Authelia sin errores de OIDC.

## Implementation Notes
