---
id: NASKS-61
title: Desplegar wger (workout/fitness tracker) reutilizando Postgres y Valkey
status: To Do
assignee: []
created_date: '2026-05-07 20:50'
updated_date: '2026-06-19 16:56'
labels:
  - app
  - business
  - auth
  - refined
dependencies:
  - NASKS-63
references:
  - 'https://github.com/wger-project/wger'
  - 'https://github.com/wger-project/docker'
  - 'https://wger.readthedocs.io/en/latest/production/docker.html'
  - 'https://github.com/wger-project/docker/blob/master/config/prod.env'
  - 'https://github.com/wger-project/docker/blob/master/docker-compose.yml'
  - 'https://wger.de/en/software/api'
priority: medium
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Objetivo

Desplegar [wger](https://github.com/wger-project/wger) — gestor self-hosted de rutinas de entrenamiento, peso y medidas — en el cluster k3s, integrado con Authelia (forward-auth) y reutilizando la infra de bases de datos compartida (`postgres` y `valkey` en namespace `databases`). Sin Postgres ni Redis dedicados.

## Dependencias

- **NASKS-63** (Habilitar forward-auth Authelia + Middleware Traefik genérico) — bloqueante **solo para la fase 3**. Las fases 1 y 2 son independientes.

## Decisiones cerradas (grilling + 2 simulacros)

| # | Decisión | Valor |
|---|---|---|
| 1 | Namespace | `business` (junto a facturascripts) |
| 2 | App móvil | **Renunciamos** — solo web tras Authelia |
| 3 | Hostname | `gym.danielramos.me` |
| 4 | Valkey DBs lógicas | `/2` cache, `/3` celery broker, `/4` celery backend |
| 5 | Sync catálogo | Solo `SYNC_EXERCISES_CELERY=True`. Resto OFF. |
| 6 | Volumen `static` | `emptyDir`, regenerado cada arranque (`DJANGO_COLLECTSTATIC_ON_STARTUP=True`) |
| 7 | Volúmenes persistentes | `/cold-data/wger/media` (HDD RAID1) + `/data/wger/celery-beat` (SSD) |
| 8 | Bootstrap admin | **Fase 2**: `admin/adminadmin` operativo (sin Authelia) — se usa para validar la app, crear rutinas dummy. **Fase 3**: con Authelia delante, `admin` ya NO es accesible (Authelia se interpone). Flujo: primer login SSO → `AUTH_PROXY_CREATE_UNKNOWN_USER` crea tu user → SQL promote a superuser → SQL DELETE admin. |
| 9 | Postgres extensions | Patrón estándar (vector/vchord/cube/earthdistance) — inocuas |
| 10 | `AUTH_PROXY_TRUSTED_IPS` | `10.42.0.0/16` (pod CIDR k3s, verificado vía VictoriaMetrics) |
| 11 | Email | `smtp-relay.system.svc.cluster.local:587`, sin auth, `DEFAULT_FROM_EMAIL=NAS <nas@mail.danielramos.me>` |
| 12 | Métricas | `EXPOSE_PROMETHEUS_METRICS=True`. Annotations en Service → VictoriaMetrics scrapea ClusterIP directo, **NO pasa por Traefik ni Authelia**, no hay conflicto con el middleware. Verificar path real (`/metrics` vs `/api/v2/metrics`) en docs upstream. Solo Service del web. Sin Flower. |
| 13 | Replicas | web=1, celery-worker=1, celery-beat=1 |
| 14 | Celery concurrency | `CELERY_WORKER_CONCURRENCY=2` |
| 15 | Init container | NO — confiar en `restartPolicy: Always`. Documentar que CrashLoopBackoff inicial mientras Postgres arranca es esperado, no error. |
| 16 | Backup Postgres | Cubierto por la infra existente |
| 17 | Imagen | Pinear versión en `versions.json`, NO `:latest`. Renovate gestiona bumps. |
| 18 | Config | Dict in-line en `wger.libsonnet` vía `u.configMap.forEnv(component, {KEY: 'val', ...})`. Patrón `facturascripts.libsonnet:61`. |
| 19 | DB password | Reusar `postgresSecrets.userWger` (importar de `lib/databases/postgres/postgres.secrets.json`). Patrón `authelia.libsonnet:68`. |
| 20 | Healthcheck | Usar `/api/v2/version/` para startup/liveness, o omitir startupProbe (evaluar al implementar). |
| 21 | `SIGNING_KEY` | Verificar al implementar si es realmente requerido. Puede ser opcional si no usamos DRF JWT. |

> Nota: existe **NASKS-62** (separar Immich `/0` y ArgoCD `/1` que actualmente comparten `/0`). Wger usa `/2-/4`, no colisiona.

## Stack & componentes

Imagen `docker.io/wger/server:<versión-pineada>` (entrada en `versions.json`), cambiando solo el `command` para los tres roles:
- **web** (Deployment) — Django + Gunicorn (8000).
- **celery-worker** (Deployment) — `celery -A wger worker -l INFO`.
- **celery-beat** (Deployment) — `celery -A wger beat -l INFO --schedule=/home/wger/celery-beat/celerybeat-schedule`.

`nginx` upstream omitido (Traefik sirve estáticos vía proxy directo o WhiteNoise — decidir al implementar).

## Reutilización de BBDD

**Postgres** (`postgres.databases.svc.cluster.local:5432`):
- Añadir entrada `userWger` en `lib/databases/postgres/postgres.libsonnet` (patrón `userAuthelia` y similares).
- Añadir entrada `userWger.DB_PASSWORD` (cluster-wide) en `lib/databases/postgres/postgres.secrets.json`.
- wger importa `postgres.secrets.json` y reusa `postgresSecrets.userWger.DB_PASSWORD` (NO duplicar).

**Valkey** (`valkey.databases.svc.cluster.local:6379`):
- `DJANGO_CACHE_LOCATION=redis://valkey.databases.svc.cluster.local:6379/2`
- `CELERY_BROKER=redis://valkey.databases.svc.cluster.local:6379/3`
- `CELERY_BACKEND=redis://valkey.databases.svc.cluster.local:6379/4`

## Variables de entorno (dict in-line en `wger.libsonnet`)

### Públicas comunes (fases 2 y 3)
```
TIME_ZONE=Europe/Madrid
TZ=Europe/Madrid
SITE_URL=https://gym.danielramos.me
CSRF_TRUSTED_ORIGINS=https://gym.danielramos.me
X_FORWARDED_PROTO_HEADER_SET=True
NUMBER_OF_PROXIES=1
WGER_INSTANCE=https://wger.de

ALLOW_REGISTRATION=False
ALLOW_GUEST_USERS=False

DJANGO_DB_ENGINE=django.db.backends.postgresql
DJANGO_DB_HOST=postgres.databases.svc.cluster.local
DJANGO_DB_PORT=5432
DJANGO_DB_NAME=wger
DJANGO_DB_USER=wger
DJANGO_PERFORM_MIGRATIONS=True
DJANGO_COLLECTSTATIC_ON_STARTUP=True

USE_CELERY=True
CELERY_WORKER_CONCURRENCY=2
CELERY_BROKER=redis://valkey.databases.svc.cluster.local:6379/3
CELERY_BACKEND=redis://valkey.databases.svc.cluster.local:6379/4
DJANGO_CACHE_BACKEND=django_redis.cache.RedisCache
DJANGO_CACHE_LOCATION=redis://valkey.databases.svc.cluster.local:6379/2

SYNC_EXERCISES_CELERY=True
SYNC_EXERCISE_IMAGES_CELERY=False
SYNC_EXERCISE_VIDEOS_CELERY=False
SYNC_INGREDIENTS_CELERY=False
CACHE_API_EXERCISES_CELERY=False

EXPOSE_PROMETHEUS_METRICS=True

EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp-relay.system.svc.cluster.local
EMAIL_PORT=587
EMAIL_USE_TLS=False
DEFAULT_FROM_EMAIL=NAS <nas@mail.danielramos.me>
```

### Adicionales en fase 3 (forward-auth)
```
AUTH_PROXY_HEADER=Remote-User
AUTH_PROXY_USER_EMAIL_HEADER=Remote-Email
AUTH_PROXY_USER_NAME_HEADER=Remote-Name
AUTH_PROXY_TRUSTED_IPS=10.42.0.0/16
AUTH_PROXY_CREATE_UNKNOWN_USER=True
```

### Secretas
- **En `postgres.secrets.json` (cluster-wide)**: `userWger.DB_PASSWORD` — wger lo importa.
- **En `wger.secrets.json` (strict)**: `SECRET_KEY` (Django). `SIGNING_KEY` solo si resulta requerido.

## Volúmenes hostPath

- `/cold-data/wger/media` → uploads custom (HDD RAID1)
- `/data/wger/celery-beat` → schedule state (SSD)
- `static` → `emptyDir`

## Layout Tanka

```
lib/databases/postgres/postgres.libsonnet  # +entrada userWger
lib/databases/postgres/postgres.secrets.json  # +userWger.DB_PASSWORD encriptado

lib/business/wger/
├── wger.libsonnet
└── wger.secrets.json

environments/business/main.jsonnet  # importar wger
environments/versions.json          # +wger.image, wger.version
```

ArgoCD genera la Application automáticamente al detectar el label `app: wger`.

## Fuera de alcance

- App móvil (renuncia explícita).
- OIDC nativo (no existe upstream).
- Sync de imágenes/vídeos/ingredientes.
- Importación masiva Open Food Facts.
- Flower para monitorización Celery.
- NetworkPolicies.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fase 1: migrationJob `postgres-create-user-wger` ejecutado con éxito; `psql -U wger -d wger` conecta
- [ ] #2 Fase 2: 3 Deployments (web/celery-worker/celery-beat) Running con réplicas 1/1/1 sin errores recurrentes en Loki
- [ ] #3 Fase 2: wger accesible en https://gym.danielramos.me con login admin/adminadmin (sin Authelia todavía); UI navegable
- [ ] #4 Fase 2: Celery worker (concurrency=2) y celery beat operativos; sync-exercises manual funciona y catalog aparece en UI
- [ ] #5 Fase 2: VictoriaMetrics scrapea métricas vía annotations en Service (`up{kubernetes_namespace="business", kubernetes_name=~"wger.*"}` devuelve 1)
- [ ] #6 Fase 3 (tras NASKS-63): IngressRoute con middleware `u.middleware.autheliaForwardAuth()`; acceso a gym.danielramos.me redirige a Authelia y entra como user SSO
- [ ] #7 Fase 3: bootstrap completado — user SSO promocionado a superuser y `admin` borrado de la DB
- [ ] #8 wger usa Postgres compartido con role+db `wger` creados por migrationJob; sin Postgres dedicado
- [ ] #9 wger usa Valkey compartido con DBs lógicas /2, /3, /4; sin Redis dedicado
- [ ] #10 Secretos (SECRET_KEY, opcionalmente SIGNING_KEY) gestionados como SealedSecret strict; DB password reusada de postgres.secrets.json (no duplicada)
- [ ] #11 Volúmenes /cold-data/wger/media (HDD RAID1) y /data/wger/celery-beat (SSD) montados y persistentes; static en emptyDir
- [ ] #12 Imagen wger pineada en versions.json (no `:latest`); Renovate puede gestionar bumps
- [ ] #13 Email vía smtp-relay.system.svc.cluster.local:587 con DEFAULT_FROM_EMAIL='NAS <nas@mail.danielramos.me>'
- [ ] #14 Solo SYNC_EXERCISES_CELERY=True; resto de SYNC_*_CELERY a False
- [ ] #15 Application de ArgoCD generada automáticamente y synced healthy
- [ ] #16 El servicio sobrevive a un reinicio del nodo sin pérdida de datos
- [ ] #17 Documentadas en la task notas reproducibles: comandos de bootstrap, DBs lógicas Valkey, break-glass si SSO falla, rollback básico
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Faseado de implementación (3 fases)

Decidido: separar BBDD (riesgo aislado), wger funcional sin auth (validación de la app pura), y forward-auth + bootstrap SSO (riesgo de integración). Cada fase es desplegable y validable independientemente.

### Fase 1 — Postgres user/db (aislada)

**Cambios:**
- Añadir entrada `userWger` en `lib/databases/postgres/postgres.libsonnet` siguiendo patrón `userAuthelia` (`createUser('wger', secrets.userWger, self.createUserMigration, self.sealedSecret)`).
- Añadir entrada `userWger.DB_PASSWORD` (cluster-wide encriptada) en `lib/databases/postgres/postgres.secrets.json`.
- Commit + push → ArgoCD aplica el migrationJob.

**Validación:**
```bash
kubectl get job -n databases postgres-create-user-wger -o jsonpath='{.status.succeeded}'
kubectl exec -n databases postgres-0 -- psql -U wger -d wger -c "SELECT current_user, current_database();"
```

Si falla, no contamina nada. Rollback = revert + drop role/db.

### Fase 2 — wger funcional SIN auth (admin/adminadmin)

> ⚠️ **Durante esta fase wger está accesible públicamente con `admin/adminadmin`**. Aceptable solo si fase 3 viene en la misma sesión o el siguiente día. NO dejar abierto durante semanas.

**Pre-implementación (verificaciones):**
- Pinear versión estable de `docker.io/wger/server` y añadir entrada en `versions.json`.
- Comandos exactos de Celery (de `wger-project/docker/docker-compose.yml`):
  - worker: `celery -A wger worker -l INFO`
  - beat: `celery -A wger beat -l INFO --schedule=/home/wger/celery-beat/celerybeat-schedule`
- Verificar path real de `/metrics` en docs upstream (¿`/metrics` o `/api/v2/metrics`?). Ajustar `u.metrics.annotations(port, path)` en consecuencia.

**Cambios en `lib/business/wger/`:**
- 3 Deployments: `wger` (web), `wger-celery-worker`, `wger-celery-beat` — misma imagen pineada, distinto `command`.
- `service` con `u.metrics.annotations('8000', '<path-verificado>')`. **Scrape interno (annotations en Service) — VictoriaMetrics scrapea ClusterIP directo, no pasa por Traefik ni Authelia.**
- `configMap` con dict in-line de variables públicas (patrón `facturascripts.libsonnet:61`). **Sin `AUTH_PROXY_*` por ahora** (se añaden en fase 3).
- `sealedSecret` strict scope con `SECRET_KEY`. `SIGNING_KEY` — verificar al implementar si es realmente requerido (puede ser opcional si no usamos DRF JWT).
- Importar `lib/databases/postgres/postgres.secrets.json` y referenciar `userWger.DB_PASSWORD`.
- `ingressRoute` **SIN middleware Authelia** — wger expuesto directo en `gym.danielramos.me`.
- Volúmenes hostPath `/cold-data/wger/media`, `/data/wger/celery-beat`, `static` emptyDir.
- Registro en `environments/business/main.jsonnet` con `u.labelApp()`.
- Entrada `wger.image` + `wger.version` en `environments/versions.json`.

**Validación post-deploy:**
1. `argocd app sync wger --grpc-web` → Synced + Healthy.
2. 3 pods Running sin reinicios:
   ```bash
   kubectl get pods -n business -l app=wger
   ```
   > NOTA: durante el primer arranque puede haber CrashLoopBackoff temporal mientras espera a Postgres (decidimos no usar init container). Esperar ~1-2 min, debe estabilizar.
3. Logs limpios en Loki:
   ```
   {namespace="business", pod=~"wger.*"} |~ "(?i)error|fail|critical|exception"
   ```
4. Acceso a `https://gym.danielramos.me` directo → login con `admin/adminadmin` → navegar UI, crear rutina dummy.
5. Probar Celery: verificar logs de worker y beat:
   ```
   {namespace="business", pod=~"wger-celery.*"}
   ```
6. Disparar sync inicial:
   ```bash
   kubectl exec -n business deploy/wger -- python manage.py sync-exercises
   ```
   Catálogo aparece en UI.
7. Scraping en VictoriaMetrics:
   ```promql
   up{kubernetes_namespace="business", kubernetes_name=~"wger.*"}
   ```
   Si devuelve 0, verificar que `/metrics` responde sin auth desde un pod del cluster:
   ```bash
   kubectl exec -n monitoring deploy/<vmagent> -- wget -qO- http://wger.business.svc.cluster.local:8000/metrics | head
   ```

### Fase 3 — Forward-auth + bootstrap SSO (cierra NASKS-63)

**Pre-requisito:** ejecutar el contenido completo de **NASKS-63** (Middleware Traefik `authelia-forwardauth` + helper `u.middleware.autheliaForwardAuth()` + `allowCrossNamespace: true` en Traefik values).

**Cambios en wger:**
- Añadir variables `AUTH_PROXY_*` al ConfigMap:
  ```
  AUTH_PROXY_HEADER=Remote-User
  AUTH_PROXY_USER_EMAIL_HEADER=Remote-Email
  AUTH_PROXY_USER_NAME_HEADER=Remote-Name
  AUTH_PROXY_TRUSTED_IPS=10.42.0.0/16
  AUTH_PROXY_CREATE_UNKNOWN_USER=True
  ```
- Modificar IngressRoute para añadir middleware `u.middleware.autheliaForwardAuth()`.
- Commit + push.

**Validación post-deploy:**
1. ArgoCD synced healthy (wger + authelia + traefik).
2. Acceso a `https://gym.danielramos.me` (navegador limpio, incógnito) → debe redirigir a Authelia → tras login + 2FA, entras a wger como tu user SSO (NO como `admin`).
3. Verificar user creado en DB:
   ```bash
   kubectl exec -n databases postgres-0 -- \
     psql -U wger -d wger -c "SELECT username, is_superuser FROM auth_user;"
   ```
   Deben aparecer `admin` (default, sin permisos elevados aún) y `<tu-username-sso>`.
4. Promocionar tu user SSO a superuser:
   ```bash
   kubectl exec -n databases postgres-0 -- \
     psql -U wger -d wger -c "UPDATE auth_user SET is_superuser=true, is_staff=true WHERE username='<tu-username>';"
   ```
5. Borrar `admin` por defecto:
   ```bash
   kubectl exec -n databases postgres-0 -- \
     psql -U wger -d wger -c "DELETE FROM auth_user WHERE username='admin';"
   ```

### Break-glass (si SSO no crea user en fase 3)

Si tras el primer login SSO `auth_user` no contiene tu user (causa probable: `AUTH_PROXY_TRUSTED_IPS` mal, headers no llegan, o `AUTH_PROXY_CREATE_UNKNOWN_USER=False` por error):

1. Port-forward al pod web saltándose Traefik:
   ```bash
   kubectl port-forward -n business deploy/wger 8000:8000
   ```
2. Acceder a `http://localhost:8000` → login con `admin/adminadmin` (todavía existe).
3. Crear superuser desde `manage.py`:
   ```bash
   kubectl exec -n business deploy/wger -- python manage.py createsuperuser
   ```
4. Investigar por qué AUTH_PROXY no funcionó (logs de wger + Authelia).

### Coste-beneficio

- **Pros:** Cada fase aísla un tipo de riesgo. Fase 2 valida wger pura (¿levanta? ¿conecta? ¿celery hace su trabajo?) sin Authelia interferiendo. Fase 3 valida solo la integración SSO sobre una app que sabemos que funciona.
- **Contras:** ventana de exposición pública de wger con `admin/adminadmin` entre fase 2 y fase 3. Mitigación: hacer fases 2 + 3 en la misma sesión o, como mucho, días consecutivos. Cambiar la password del `admin` en cuanto entres por primera vez en fase 2 si la ventana se alarga.
<!-- SECTION:PLAN:END -->
