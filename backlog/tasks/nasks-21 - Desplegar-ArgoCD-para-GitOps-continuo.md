---
id: NASKS-21
title: Desplegar ArgoCD para GitOps continuo
status: In Progress
assignee: []
created_date: '2026-03-15 21:06'
updated_date: '2026-03-15 21:41'
labels:
  - infrastructure
  - gitops
dependencies:
  - NASKS-17
references:
  - lib/system/ (donde irá argocd.libsonnet)
  - environments/system/spec.json
  - .github/workflows/validate.yml (CI existente donde añadir el export)
documentation:
  - >-
    https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/
  - 'https://tanka.dev/exporting/'
  - 'https://argo-cd.readthedocs.io/en/stable/user-guide/jsonnet/'
  - >-
    https://raw.githubusercontent.com/authelia/authelia/master/docs/content/integration/openid-connect/clients/argocd/index.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Instalar y configurar ArgoCD en el cluster K3s para gestionar los despliegues de forma declarativa via GitOps.

## Contexto

Actualmente los despliegues se hacen manualmente con `tk apply environments/<ns> --auto-approve=always`. Con ArgoCD, el cluster se sincronizará automáticamente desde el repo en GitHub, y los recursos huérfanos (como los Secrets legacy de antes de Sealed Secrets) se limpiarán con prune.

## Enfoque: CI export + ArgoCD lee YAMLs planos

En vez de un CMP sidecar (complejo de mantener: imagen custom, patching de argocd-repo-server, debugging opaco), usamos la CI que ya existe para generar los manifiestos:

1. **CI** (GitHub Actions): en cada push a main, ejecuta `tk export dist/ environments/ --recursive` y pushea el resultado a una rama `manifests`
2. **ArgoCD**: lee los YAMLs planos de la rama `manifests`, sin plugins ni sidecars

### Ventajas
- Zero config en ArgoCD — solo lee YAMLs de un directorio
- La CI ya existe y funciona (validate.yml)
- Debugging trivial: los YAMLs generados son visibles en la rama
- No hay imagen custom que mantener

### Workflow

```
push a main → CI: jb install + tk export → push a rama manifests → ArgoCD sync
```

### Estructura de la rama manifests

```
dist/
  arr/
    norznab-deployment.yaml
    norznab-service.yaml
    ...
  auth/
    authelia-deployment.yaml
    ...
  databases/
  media/
  monitoring/
  system/
  dashboard/
```

### Estructura de Applications

Una Application por environment (7 total), todas leyendo de la rama `manifests`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: media
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/DanielRamosAcosta/nas-k3s.git
    targetRevision: manifests
    path: dist/media
  destination:
    server: https://kubernetes.default.svc
    namespace: media
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Recursos que genera ArgoCD

ArgoCD se instala en su propio namespace `argocd` con:
- Deployments: argocd-server, argocd-repo-server, argocd-application-controller, argocd-redis, argocd-dex-server
- CRDs: Application, AppProject, ApplicationSet
- IngressRoute para acceso via Traefik
- OIDC con Authelia para SSO
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ArgoCD instalado en namespace `argocd` via Helm chart + Jsonnet overlays
- [ ] #2 CI genera manifiestos YAML con `tk export` y los pushea a rama `manifests`
- [ ] #3 8 Applications creadas (7 environments + argocd mismo) leyendo de rama `manifests`
- [ ] #4 syncPolicy en modo manual (no auto-sync) — ArgoCD detecta drift pero NO aplica cambios automáticamente
- [ ] #5 Webhook de GitHub configurado para notificar a ArgoCD en cada push (sync rápido sin esperar polling)
- [ ] #6 IngressRoute configurado para acceso via argocd.danielramos.me
- [ ] #7 OIDC con Authelia para login en ArgoCD (grupo admins = role:admin)
- [ ] #8 ArgoCD usa Valkey externo (no Redis propio)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Plan de implementación

### Fase 1: 2 agentes en paralelo

**Agente `sre-ci`** (worktree, PR independiente) — Workflow de CI
1. Modificar `.github/workflows/validate.yml`:
   - Añadir `permissions: contents: write`
   - Añadir step `tk export dist/ environments/ --recursive --format '{{env.spec.namespace}}/{{.kind}}-{{.metadata.name}}'`
   - Añadir step `peaceiris/actions-gh-pages@v4` para push a rama `manifests`
2. Crear PR, verificar que la CI genera la rama `manifests` correctamente
3. No toca ningún otro fichero

**Agente `sre-argocd`** (main, secuencial) — Todo lo demás
4. Añadir chart `argo-cd` v9.4.10 de `https://argoproj.github.io/argo-helm` a `chartfile.yaml`
5. `tk tool charts vendor` para descargar el chart
6. Crear `environments/argocd/spec.json` (namespace: argocd) y `main.jsonnet`
7. Crear `lib/system/argocd.libsonnet` con `helm.template()` + Helm values:
   - `dex.enabled: false`
   - `redis.enabled: false`, `redisSecretInit.enabled: false`
   - `externalRedis.host: valkey.databases.svc.cluster.local`
   - `configs.params.server.insecure: true`
   - `configs.cm` con URL + OIDC (referenciando secret con `$argocd-oidc-secret:client-secret`)
   - `configs.rbac.policy.csv: "g, admins, role:admin"`
8. Añadir overlays Jsonnet: IngressRoute, SealedSecrets, Applications (8 total)
9. Generar OIDC secrets con `docker run authelia/authelia crypto ...`
10. Encriptar con kubeseal: OIDC client secret (strict, argocd ns) + webhook secret
11. Crear `lib/system/argocd.secrets.json`
12. Actualizar `lib/auth/authelia.secrets.json` con digest del nuevo cliente
13. Actualizar authelia config (`authelia.config.yml`) con clientes OIDC argocd + argocd-cli
14. Añadir versión del chart a `lib/versions.json`
15. Verificar con `tk eval environments/argocd`
16. Commit y push

### Fase 2: Team lead (después de fase 1)

17. Deploy inicial: `tk apply environments/argocd`
18. Deploy authelia actualizado: `tk apply environments/auth`
19. Verificar UI en argocd.danielramos.me (interacción usuario)
20. Verificar login OIDC con Authelia (interacción usuario)
21. Configurar webhook con `gh api`
22. Verificar que las Applications detectan el estado actual del cluster
23. Hacer primer Sync manual de un environment de prueba (interacción usuario)
24. Documentar nuevo workflow en CLAUDE.md
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Configuración OIDC con Authelia

ArgoCD necesita **dos clientes OIDC** en Authelia:

### 1. Cliente web (`argocd`)
- `client_secret`: hash pbkdf2-sha512 (el plaintext se pone en argocd-cm)
- `redirect_uris`: `https://argocd.danielramos.me/auth/callback`
- `scopes`: openid, groups, email
- `token_endpoint_auth_method`: client_secret_basic
- `require_pkce`: false

### 2. Cliente CLI (`argocd-cli`)
- `public`: true (sin secret)
- `redirect_uris`: `http://localhost:8085/auth/callback`
- `scopes`: openid, offline_access, groups, email
- `require_pkce`: true, `pkce_challenge_method`: S256
- `token_endpoint_auth_method`: none

### ArgoCD ConfigMap (argocd-cm)
```yaml
oidc.config: |
  name: Authelia
  issuer: https://auth.danielramos.me
  clientID: argocd
  clientSecret: <plaintext-secret>
  cliClientID: argocd-cli
  requestedScopes: [openid, email, groups]
  enableUserInfoGroups: true
  userInfoPath: /api/oidc/userinfo
```

### RBAC (argocd-rbac-cm)
```csv
g, admins, role:admin
```
Mapea el grupo `admins` de Authelia al role `admin` de ArgoCD.

### Secretos necesarios
- `ARGOCD_OIDC_CLIENT_SECRET`: plaintext del client_secret (para argocd-cm)
- `ARGOCD_OIDC_CLIENT_SECRET_DIGEST`: hash pbkdf2-sha512 (para authelia config)
- Ambos se encriptan con Sealed Secrets (el digest en authelia strict, el plaintext en argocd strict)

## Generación de secretos OIDC para ArgoCD

Usar el CLI de Authelia (via Docker) para generar client ID y secret:

### Client ID
```bash
docker run --rm authelia/authelia:latest authelia crypto rand --length 72 --charset rfc3986
```

### Client Secret (genera plaintext + digest de una vez)
```bash
docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986
```
Esto devuelve dos líneas:
1. **Random Password**: el plaintext (va en argocd-cm como `clientSecret`)
2. **Digest**: el hash pbkdf2-sha512 (va en authelia config como `client_secret`)

Hacer lo mismo para el client ID del cliente web (`argocd`). El cliente CLI (`argocd-cli`) es público y no necesita secret.

Referencia: https://www.authelia.com/integration/openid-connect/frequently-asked-questions/

## DNS

`argocd.danielramos.me` ya dado de alta en Cloudflare (CNAME → nas.danielramos.me). No hace falta tocar DNS.

## Sync policy: manual (no destructivo)

ArgoCD se configura SIN auto-sync. El flujo es:
1. Push a main → CI genera YAMLs → push a rama `manifests`
2. Webhook notifica a ArgoCD → ArgoCD detecta diff instantáneamente
3. En la UI de ArgoCD se ve el diff (qué cambiaría)
4. El operador revisa y hace click en "Sync" manualmente

Esto evita que un push roto tumbe servicios automáticamente. Cuando tengamos confianza, se puede habilitar auto-sync por environment.

```yaml
spec:
  syncPolicy: {}  # sin automated = manual sync
```

## Webhook de GitHub

Para que ArgoCD no dependa del polling (por defecto cada 3 minutos), configuramos un webhook:

1. En ArgoCD, el servidor ya expone `/api/webhook` para recibir notificaciones
2. En GitHub repo settings → Webhooks → Add webhook:
   - **Payload URL**: `https://argocd.danielramos.me/api/webhook`
   - **Content type**: `application/json`
   - **Secret**: un shared secret (configurado también en argocd-secret)
   - **Events**: Just the push event
3. Configurar el secret del webhook en `argocd-secret`:
   ```yaml
   webhook.github.secret: <shared-secret>
   ```
4. Encriptar con Sealed Secrets

Con esto, ArgoCD detecta cambios en segundos en vez de minutos.

## Crear webhook con gh CLI

En vez de crear el webhook manualmente desde la web, usar `gh api`:

```bash
# Generar shared secret
SECRET=$(openssl rand -hex 32)
echo "Webhook secret: $SECRET"

# Crear webhook en GitHub
gh api repos/DanielRamosAcosta/nas-k3s/hooks -f name=web \
  -f 'config[url]=https://argocd.danielramos.me/api/webhook' \
  -f 'config[content_type]=application/json' \
  -f "config[secret]=$SECRET" \
  -f 'events[]'=push \
  -f active=true

# Encriptar el secret para argocd-secret
echo -n "$SECRET" | ./scripts/encrypt-secret.sh system argocd-secret
```

El valor encriptado se añade en argocd-secret bajo la key `webhook.github.secret`.

## Configuración de ArgoCD: ConfigMaps y Secrets

ArgoCD NO usa ficheros de config ni env vars. Se configura con recursos de K8s en el namespace `argocd`:

| Recurso | Propósito |
|---------|----------|
| `argocd-cm` (ConfigMap) | Config principal: URL externa, OIDC, customizaciones de recursos |
| `argocd-secret` (Secret) | Admin password, webhook secret, TLS certs |
| `argocd-cmd-params-cm` (ConfigMap) | Flags de componentes: log format, insecure mode, etc. |
| `argocd-rbac-cm` (ConfigMap) | Políticas RBAC: mapeo de grupos a roles |

### Referencia de secrets desde ConfigMaps

En `argocd-cm` se pueden referenciar secrets con la sintaxis `$<secret-name>:<key>`. El Secret referenciado DEBE tener el label `app.kubernetes.io/part-of: argocd`.

```yaml
# argocd-cm
oidc.config: |
  clientID: argocd
  clientSecret: $argocd-oidc-secret:client-secret

# argocd-oidc-secret (SealedSecret → Secret)
metadata:
  labels:
    app.kubernetes.io/part-of: argocd
data:
  client-secret: <base64-plaintext>
```

Así el plaintext del OIDC client secret vive en un SealedSecret separado, no en el ConfigMap. ArgoCD lo resuelve automáticamente al arrancar.

### Implicación para la implementación

El `argocd.libsonnet` necesita generar:
- 4 ConfigMaps: `argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm`, `argocd-notifications-cm` (vacío)
- 1 Secret: `argocd-secret` (admin password, webhook secret)
- 1 SealedSecret adicional: `argocd-oidc-secret` (client secret OIDC, con label `part-of: argocd`)
- Todos con labels `app.kubernetes.io/name` y `app.kubernetes.io/part-of: argocd`

## Decisiones de arquitectura

### Environment propio
ArgoCD vive en `environments/argocd/` con namespace `argocd` (no en system).

### Helm chart + overlays Jsonnet
ArgoCD se instala via Helm chart (como kubernetes-dashboard) con `helm.template()`. Los CRDs y RBAC vienen del chart. Las customizaciones se hacen en Jsonnet encima:
- IngressRoute para argocd.danielramos.me
- SealedSecrets (OIDC, webhook)
- ConfigMaps (argocd-cm con OIDC, argocd-rbac-cm)
- Applications (7, una por environment)

Chart oficial: `https://argoproj.github.io/argo-helm` → `argo-cd`

### ArgoCD se gestiona a sí mismo
El deploy inicial es manual con `tk apply environments/argocd`. Después, ArgoCD tiene una Application para su propio environment y se hace sync a sí mismo. Sync manual (no destructivo), así siempre revisamos el diff antes de aplicar. Fallback: `tk apply` manual si ArgoCD se rompe.

### TLS termination
ArgoCD server corre en modo insecure (HTTP plano). La cadena TLS es: Cliente → Cloudflare (TLS) → Traefik (TLS) → ArgoCD (HTTP). Se configura con `server.insecure: "true"` en `argocd-cmd-params-cm`, o como Helm value.

### Redis: Valkey compartido
ArgoCD usa el Valkey existente en `valkey.databases.svc.cluster.local:6379`. No se despliega Redis dedicado. Helm value: `redis.enabled: false` + config para apuntar al Valkey externo.

### Repo público
El repo es público. ArgoCD no necesita credenciales para leerlo.

### Formato de tk export
Se usa el formato por defecto de `tk export` (sin flag `--format`).

## Helm values clave para el chart argo-cd (v9.4.10)

Extraído del values.yaml oficial:

```yaml
# Deshabilitar Dex (usamos OIDC directo con Authelia)
dex:
  enabled: false

# Deshabilitar Redis interno (usamos Valkey externo)
redis:
  enabled: false
redisSecretInit:
  enabled: false

# Apuntar a Valkey externo (sin password, Valkey no tiene auth configurado)
externalRedis:
  host: valkey.databases.svc.cluster.local
  port: 6379

# TLS: ArgoCD en modo insecure (Traefik hace TLS termination)
configs:
  params:
    server.insecure: true

  # OIDC con Authelia
  cm:
    url: https://argocd.danielramos.me
    admin.enabled: false  # solo OIDC, sin admin local
    oidc.config: |
      name: Authelia
      issuer: https://auth.danielramos.me
      clientID: <generated>
      clientSecret: $argocd-oidc-secret:client-secret
      cliClientID: <generated>
      requestedScopes: [openid, email, groups]
      enableUserInfoGroups: true
      userInfoPath: /api/oidc/userinfo

  # RBAC: grupo admins de Authelia → role:admin
  rbac:
    policy.csv: |
      g, admins, role:admin
    scopes: "[groups]"
```

## Qué son las Applications

Una Application es un CRD de ArgoCD que le dice: "vigila este directorio en este repo/rama y sincronízalo con este namespace del cluster". Es el recurso principal de ArgoCD.

Cada Application define:
- **source**: de dónde leer manifiestos (repo + rama + path)
- **destination**: dónde aplicarlos (cluster + namespace)
- **syncPolicy**: cómo sincronizar (manual/automático, prune, selfHeal)

Nosotros tendremos 8 Applications:
- `arr` → lee `dist/arr/` de rama `manifests`, aplica en namespace `arr`
- `auth` → lee `dist/auth/`, aplica en `auth`
- `databases` → lee `dist/databases/`, aplica en `databases`
- `dashboard` → lee `dist/dashboard/`, aplica en `dashboard`
- `media` → lee `dist/media/`, aplica en `media`
- `monitoring` → lee `dist/monitoring/`, aplica en `monitoring`
- `system` → lee `dist/system/`, aplica en `system`
- `argocd` → lee `dist/argocd/`, aplica en `argocd` (se gestiona a sí mismo)

Todas con `syncPolicy: {}` (manual) para que ArgoCD detecte drift pero no aplique sin nuestra aprobación.

## CI: Push a rama manifests

`GITHUB_TOKEN` puede pushear a ramas no protegidas con `permissions: contents: write`.

Usamos `peaceiris/actions-gh-pages@v4` para publicar `dist/` como rama `manifests`:

```yaml
permissions:
  contents: write

steps:
  - uses: actions/checkout@v4
  - uses: kobtea/setup-jsonnet-action@v2
  - uses: unfunco/setup-tanka@1.0.0-alpha.1
    with:
      tanka-version: "0.36.2"
  - run: jb install && tk tool charts vendor
  - run: tk export dist/ environments/ --recursive
  - uses: peaceiris/actions-gh-pages@v4
    with:
      github_token: ${{ secrets.GITHUB_TOKEN }}
      publish_dir: ./dist
      publish_branch: manifests
```

Alternativa manual con `git push --force` también funciona pero `actions-gh-pages` es más limpio.

Requisito: la rama `manifests` NO debe tener branch protection.

## Formato de tk export (actualizado)

El formato por defecto NO funciona con export recursivo — genera todos los ficheros en un directorio plano y hay colisiones de nombres entre environments (ej: dos SealedSecrets `config-secret-json-sealed-secret` en media).

**Formato correcto:**
```bash
tk export dist/ environments/ --recursive --format '{{env.spec.namespace}}/{{.kind}}-{{.metadata.name}}'
```

Esto genera subdirectorios por namespace:
```
dist/
  arr/
    Deployment-norznab.yaml
    Service-norznab.yaml
    ...
  media/
    StatefulSet-immich.yaml
    ...
  ...
```

Cada Application de ArgoCD apunta a `dist/<namespace>/` — exactamente un subdirectorio por Application.

## Paths en la rama manifests

`peaceiris/actions-gh-pages` publica el contenido de `publish_dir` como raíz de la rama. Con `publish_dir: ./dist`, la rama `manifests` tendrá:

```
arr/
  Deployment-norznab.yaml
media/
  StatefulSet-immich.yaml
...
```

Sin prefijo `dist/`. Las Applications apuntan a `path: arr`, `path: media`, etc. (NO `path: dist/arr`).

## Herramientas verificadas

Todas disponibles localmente:
- Docker 28.5.2 (para `authelia crypto`)
- Helm v4.0.4 (para `helm.template()` en Tanka)
- kubeseal (para Sealed Secrets)
- tk v0.36.2 + jb (Tanka + jsonnet-bundler)
- `tk tool charts vendor` funciona
- Acceso al cluster K8s
- Acceso a GitHub (gh CLI)

## Interacción necesaria del usuario

La Fase 1 (CI + Helm chart + OIDC) es 100% autónoma. En la Fase 2 se necesita interacción para:
- Verificar que la UI de ArgoCD carga correctamente en argocd.danielramos.me
- Verificar que el login OIDC con Authelia funciona
- Revisar el diff de las Applications y hacer el primer Sync manual
<!-- SECTION:NOTES:END -->
