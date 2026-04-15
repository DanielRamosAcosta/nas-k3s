---
id: NASKS-47
title: Desplegar FacturaScripts en el NAS (ERP/facturación)
status: Done
assignee: []
created_date: '2026-04-02 22:52'
updated_date: '2026-04-12 01:06'
labels:
  - refined
  - new-service
dependencies: []
references:
  - 'https://github.com/NeoRazorX/facturascripts'
  - 'https://hub.docker.com/r/facturascripts/facturascripts'
  - >-
    https://github.com/FacturaScripts/docker-facturascripts/blob/master/docker-compose.yml
  - lib/media/booklore/booklore.libsonnet (patrón de referencia)
  - lib/databases/postgres/postgres.libsonnet (creación de usuario DB)
  - >-
    repos/others/facturascripts/ENV_VARS.md (análisis de variables de
    configuración)
documentation:
  - 'https://facturascripts.com/documentacion'
priority: medium
ordinal: 0.0019073486328125
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Contexto

[FacturaScripts](https://github.com/NeoRazorX/facturascripts) es un ERP/software de facturación open-source (LGPL) orientado a pequeñas empresas. Está construido con PHP 8+ / Bootstrap 5 y necesita MySQL, MariaDB o PostgreSQL como base de datos.

Existe una [imagen Docker oficial](https://hub.docker.com/r/facturascripts/facturascripts) (`facturascripts/facturascripts`) que incluye Apache, PHP y todas las extensiones necesarias. Soporta arm64. La última versión estable es `2025.81`.

## Objetivo

Dar de alta FacturaScripts como un nuevo servicio en el stack del NAS, siguiendo el patrón estándar del repo (Jsonnet + Tanka, SealedSecrets, IngressRoute con Traefik).

## Decisiones de diseño

- **Categoría**: nueva categoría `business/` en `lib/` y `environments/` — semánticamente correcto y deja espacio para futuras herramientas de gestión (CRM, inventario, etc.)
- **Namespace**: `business`
- **Dominio**: `facturas.danielramos.me`
- **Base de datos**: reutilizar la instancia de **PostgreSQL** existente (`postgres.databases.svc.cluster.local:5432`), creando un usuario/base de datos dedicado `facturascripts` (mismo patrón que immich, authelia, sftpgo, grafana, invidious)
- **Configuración por archivo `config.php`** (no env vars):
  - **Justificación**: FacturaScripts **no lee variables de entorno**. La configuración se define mediante constantes PHP en `config.php`, creado durante la instalación. El método `Tools::config()` busca constantes definidas con `define()`, no `getenv()`. Por tanto, inyectar `FS_DB_*` como env vars no tendría efecto.
  - **Estrategia**: template `config.php` en ConfigMap con placeholder `${FS_DB_PASS}` + SealedSecret con la contraseña + init container con `envsubst` que genera el archivo final en un emptyDir compartido.
  - **ConfigMap** (`u.configMap.forFile`): template `config.php` con toda la config pública (DB host, port, user, name, timezone, idioma) y `${FS_DB_PASS}` como placeholder para la contraseña.
  - **SealedSecret cluster-wide** (`facturascripts-db`): solo `FS_DB_PASS` — la contraseña se encripta una vez cluster-wide y se reutiliza en `postgres.secrets.json` (Job createUser) y `facturascripts.secrets.json` (init container del servicio).
  - **Init container**: usa la misma imagen de FacturaScripts (Debian con Apache+PHP, incluye `envsubst` vía `gettext-base`). Lee el template del ConfigMap, sustituye `${FS_DB_PASS}` desde el SealedSecret como env var, escribe el `config.php` resultante en un emptyDir.
  - **Main container**: monta el emptyDir con `subPath` en `/var/www/html/config.php`.
- **Almacenamiento** — dos hostPath con ubicación diferenciada según perfil de uso:
  - `/var/www/html/Plugins` → `/data/facturascripts/plugins` (**SSD**) — ficheros PHP cargados en cada request, rendimiento importa.
  - `/var/www/html/MyFiles` → `/cold-data/facturascripts/myfiles` (**HDD**) — PDFs de facturas, adjuntos, documentos legales. Datos de largo plazo que crecen con el tiempo y no requieren velocidad de acceso (mismo criterio que fotos de Immich en cold-data).
  - **Justificación**: montar solo lo necesario es más kubernetes-native. El código de la app viene de la imagen y es inmutable — las actualizaciones se gestionan cambiando la versión de la imagen en `versions.json`, no desde el panel admin. `Dinamic/` (cache autogenerada) se regenera al arrancar y no necesita persistencia.
- **Puerto**: el contenedor expone el puerto 80 (Apache)
- **Auth**: solo login nativo de FacturaScripts (usuario admin + contraseña).
  - **Justificación**: no existe precedente de middleware Traefik de Authelia en el repo (todos los servicios que integran Authelia lo hacen vía OIDC a nivel de aplicación). FacturaScripts no soporta OIDC nativamente. No vale la pena crear un patrón nuevo solo para esto. Mejora futura: desarrollar un plugin OIDC para FacturaScripts que integre con Authelia.
- **Probes**: `u.probes.withStartup.http('/', 80)` con failureThreshold default (30 → ventana de 5 min). Suficiente para una app PHP — la inicialización de DB no debería tardar más de 30s. Nota: durante el setup inicial, `/` devuelve 200 (wizard), lo cual es aceptable — el pod arranca y el admin completa el setup manualmente.
- **Sin usuario admin preconfigurado**: `FS_INITIAL_USER`/`FS_INITIAL_PASS` no se definen en el config.php. El usuario admin se crea manualmente en el primer acceso. No vale la pena complicar el SealedSecret por un one-time setup.
- **Plugins habilitados**: no se restringe la instalación de plugins desde la UI (`FS_DISABLE_ADD_PLUGINS` no se define). El hostPath de `/Plugins` está persistido precisamente para esto.
- **Resource limits**: no se configuran (ningún otro servicio en el repo los usa)
- **Réplicas**: 1 (StatefulSet, patrón estándar)
- **Patrón de referencia**: `lib/media/booklore/booklore.libsonnet`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pod de FacturaScripts corriendo y healthy en el cluster
- [ ] #2 Base de datos PostgreSQL creada con usuario dedicado
- [ ] #3 Accesible vía IngressRoute en el dominio configurado
- [ ] #4 Secrets encriptados con SealedSecrets (sin plaintext en git)
- [ ] #5 ArgoCD detecta y gestiona la app automáticamente
- [ ] #6 Manifests exportados correctamente con tk export
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Paso 1: Crear usuario PostgreSQL para FacturaScripts

Añadir en `lib/databases/postgres/postgres.libsonnet` un nuevo `createUser` (como immich, authelia, etc.):

1. Generar contraseña segura para la DB
2. Encriptar cluster-wide: `echo -n 'PASS' | ./scripts/encrypt-secret.sh --cluster-wide`
3. Añadir la entrada `userFacturascripts` en `postgres.secrets.json` con el valor encriptado
4. Añadir `userFacturascripts: self.createUser('facturascripts', secrets.userFacturascripts, self.createUserMigration, self.sealedSecret)` en el module de postgres
5. **Verificar**: `tk eval environments/databases | jq '.[] | select(.metadata.name | contains("facturascripts"))'`

### Paso 2: Añadir versión a `versions.json`

```json
"facturascripts": {
  "image": "docker.io/facturascripts/facturascripts",
  "version": "2025.81"
}
```

**Verificar**: `jq '.facturascripts' lib/versions.json`

### Paso 3: Crear el módulo Jsonnet

Crear `lib/business/facturascripts/facturascripts.libsonnet` siguiendo el patrón de booklore:

- **StatefulSet** con un contenedor + init container:
  - **Init container** (misma imagen FacturaScripts):
    - Monta ConfigMap con template `config.php` en `/mnt/config-template/`
    - Recibe `FS_DB_PASS` como env var desde SealedSecret (`u.envVars.fromSealedSecret`)
    - Ejecuta: `envsubst < /mnt/config-template/config.php > /mnt/config/config.php`
    - Escribe resultado en emptyDir montado en `/mnt/config/`
  - **Main container**:
    - Puerto 80 (`http`)
    - volumeMount emptyDir `/mnt/config/config.php` → `/var/www/html/config.php` (subPath)
    - volumeMount `/var/www/html/Plugins` → hostPath `/data/facturascripts/plugins` (SSD)
    - volumeMount `/var/www/html/MyFiles` → hostPath `/cold-data/facturascripts/myfiles` (HDD)
    - env `TZ=Atlantic/Canary`
    - Probes: `u.probes.withStartup.http('/', 80)`
- **Service**: `k.util.serviceFor(self.statefulSet)`
- **ConfigMap**: `u.configMap.forFile('config.php', configTemplate)` — template PHP con placeholder `${FS_DB_PASS}`
- **SealedSecret** (cluster-wide): `u.sealedSecret.wide.forEnvNamed('facturascripts-db', { FS_DB_PASS: ... })`
- **IngressRoute**: `u.ingressRoute.from(self.service, 'facturas.danielramos.me')`

**Template config.php**:
```php
<?php
define('FS_DB_TYPE', 'postgresql');
define('FS_DB_HOST', 'postgres.databases.svc.cluster.local');
define('FS_DB_PORT', 5432);
define('FS_DB_NAME', 'facturascripts');
define('FS_DB_USER', 'facturascripts');
define('FS_DB_PASS', '${FS_DB_PASS}');
define('FS_LANG', 'es_ES');
define('FS_TIMEZONE', 'Atlantic/Canary');
```

**Verificar**: `tk eval environments/business 2>&1 | head -5` — sin errores

### Paso 4: Crear el environment de Tanka

1. `environments/business/main.jsonnet` — importa facturascripts y lo pasa a `u.Environment()`
2. `environments/business/spec.json` — namespace `business`, apiServer `https://localhost:6443`

**Verificar**: `tk eval environments/business | jq 'keys'`

### Paso 5: Crear secrets file

1. Copiar el valor encriptado de la contraseña (el mismo del paso 1) a `lib/business/facturascripts/facturascripts.secrets.json`
2. Estructura: `{ "facturascripts": { "FS_DB_PASS": "<encrypted>" } }`
3. Verificar que no hay plaintext

### Paso 6: Exportar y verificar manifests

```bash
tk export dist/ environments/business --format '{{index .metadata.labels "app"}}/{{.kind}}-{{.metadata.name}}'
```

Revisar YAMLs generados — confirmar que:
- El ConfigMap contiene el template con `${FS_DB_PASS}` (placeholder, no valor real)
- El SealedSecret tiene la contraseña encriptada
- El StatefulSet tiene init container + main container con los volumeMounts correctos
- El emptyDir está definido como volumen

### Paso 7: Deploy vía ArgoCD

1. Commit + push a main
2. CI exporta a rama `manifests`
3. ArgoCD detecta la nueva app `facturascripts` automáticamente
4. Sync manual desde ArgoCD
5. Verificar pod healthy + acceso a `facturas.danielramos.me`

### Paso 8: Configuración inicial

1. Acceder a `facturas.danielramos.me`
2. La DB debería estar preconfigurada vía `config.php` — el wizard puede que pida solo crear el usuario admin
3. Crear usuario admin con contraseña segura
<!-- SECTION:PLAN:END -->
