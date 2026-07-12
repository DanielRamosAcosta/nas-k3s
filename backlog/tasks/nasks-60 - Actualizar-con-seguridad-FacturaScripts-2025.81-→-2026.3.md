---
id: NASKS-60
title: Actualizar con seguridad FacturaScripts 2025.81 → 2026.3
status: Done
assignee: []
created_date: '2026-05-07 20:44'
updated_date: '2026-07-12 16:40'
labels:
  - business
  - facturascripts
  - upgrade
dependencies: []
references:
  - 'https://github.com/DanielRamosAcosta/nas-k3s/pull/75'
  - 'https://github.com/NeoRazorX/facturascripts/releases/tag/v2026'
  - 'https://github.com/NeoRazorX/facturascripts/releases/tag/v2026.1'
  - 'https://github.com/NeoRazorX/facturascripts/releases/tag/v2026.3'
  - 'https://facturascripts.com/publicaciones/facturascripts-2026-novedades'
  - 'https://facturascripts.com/publicaciones/cambios-en-el-core-2026'
  - >-
    https://github.com/NeoRazorX/facturascripts/security/advisories/GHSA-cjfx-qhwm-hf99
  - 'https://facturascripts.com/plugins/verifactu'
  - 'https://github.com/FacturaScripts/Verifactu'
  - lib/business/facturascripts/facturascripts.libsonnet
  - lib/versions.json
priority: medium
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Actualizar FacturaScripts de `2025.81` a `2026.3` (salto **mayor anual**). El diff de infra es trivial (1 línea en `lib/versions.json`), pero el riesgo real es de runtime: migraciones de schema irreversibles, un nuevo motor de cálculo fiscal (Calculator) y la **necesidad de actualizar el plugin Verifactu a la vez** (la v0.84 instalada no es compatible con 2026.x). Requiere dump previo, test en una copia de la DB y verificación funcional del IVA/Verifactu antes de promover.

> **Decisión de versión objetivo: 2026.3** (no 2026.1, que es lo que propone el PR #75 de Renovate). Motivo: el rediseño del Calculator ya entra en 2026, y 2026.3 añade los fixes de widgets de 2026.2 + endurecimiento de seguridad y es la versión más alta para la que el plugin Verifactu declara compatibilidad (`2026.1–2026.3`). Ir directo a 2026.3 evita encadenar varias migraciones de schema. Consecuencia operativa: **cerrar el PR #75** y hacer el bump manual a `2026.3` (o dejar que Renovate reabra el bump a 2026.3).

## 🎯 Contexto funcional

FacturaScripts es la app de contabilidad/facturación del homelab (namespace `business`). Renovate ha abierto un salto mayor anual cuyo impacto no es visible en el diff de jsonnet:

- En **v2026** se rediseña el Calculator para soportar IVA intracomunitario, importación, exportación e inversión de sujeto pasivo → **cambia el motor de cálculo de impuestos**. Un fallo aquí corrompe importes fiscales, no solo "no arranca".
- FS aplica **migraciones de schema irreversibles** al arrancar. Sin dump previo no hay rollback limpio de datos contables.
- El plugin de **cumplimiento AEAT (Verifactu)** instalado es de la serie 2025 y **no es compatible con 2026.x**: hay que actualizarlo en el mismo paso o se queda inoperativo.

Por eso este upgrade no puede tratarse como un bump rutinario de Renovate: amerita revisión humana del comportamiento fiscal, no solo que el pod quede `Ready`.

## ⚙️ Contexto técnico

### Despliegue
- **Diff**: 1 línea en `lib/versions.json` (`2025.81` → `2026.3`); CI verde solo valida que el jsonnet compila, no dice nada del runtime.
- **Imagen/entorno**: `docker.io/facturascripts/facturascripts`. La imagen actual ya corre **PHP 8.4.17** → el requisito de PHP 8.1 que FS hace obligatorio en 2026.3 **ya está cubierto**, no es un bloqueo.
- **Plugin Verifactu**: vive en hostPath `/data/facturascripts/plugins/Verifactu`, montado read-write en `/var/www/html/Plugins` (`facturascripts.libsonnet:26,51`). **No va en la imagen ni se despliega por CI/GitOps** — se coloca a mano en el filesystem del NAS. El `rsync` que hay en el libsonnet es solo para el backup diario de MyFiles, no para plugins.
  - **Código v1.1 ya disponible localmente** en `/Users/danielramos/Documents/repos/apps/facturascript/verifactu` (rama con commit `Update Verifactu plugin to v1.1`; `facturascripts.ini`: `version = 1.1`, `min_version = 2026.1`, `require_php = 'soap'`). Remoto git: `nas:/cold-data/git/dani/apps/facturascript/verifactu.git`.
  - **Despliegue en el upgrade = subir esa carpeta por `rsync` al hostPath**, reemplazando la v0.84 (mismo patrón manual con el que se colocaron los demás plugins). Aproximadamente: `rsync -a --delete <repo-local>/ nas:/data/facturascripts/plugins/Verifactu/` (excluyendo `.git/`). Hacerlo en el mismo paso que el bump del core (AC#2), tras el snapshot del hostPath (AC#4).
  - ✅ **`require_php = 'soap'`**: verificado (2026-07-12) que la extensión PHP SOAP está presente en la imagen `2026.3` (`php -m | grep soap`) — y también en la `2025.81` actual, donde Verifactu v0.84 ya corre. El core no la requiere (su `composer.json` no lista `ext-soap`); la trae el build de la imagen. No es un bloqueo.
- **Migraciones**: FS las aplica al arrancar contra `/deploy`, que es el startup probe (`facturascripts.libsonnet:38`). En majors puede tardar varios minutos y son **irreversibles** sin dump previo. El changelog de migraciones queda en `MyFiles/{migrations.json,db-changelog.json,db-updater.json}`.
- **MyFiles**: hostPath `/data/facturascripts/myfiles` con rsync diario a `/cold-data/contabilidad` (cron `0 3 * * *`). El resto de `/data/facturascripts` (plugins + estado) **no** tiene esa copia.
- **Snapper**: verificado en el NAS (2026-07-12) que snapper cubre **solo subvolúmenes de `/cold-data`** (config `contabilidad` → `/cold-data/contabilidad`, con `.snapshots`). **`/data` NO tiene config de snapper** ni `.snapshots` (aunque es btrfs, en el nvme raíz). Consecuencia: el snapshot pre-upgrade de plugins/estado de `/data/facturascripts` **no lo cubre snapper** → se hace con el `.zip` manual de AC#4 (o, alternativamente, un snapshot btrfs puntual de `/` a mano).
- **DB**: **sí existe backup automatizado** (corrige la nota original) — `/cold-data/postgres-backups/` contiene base backups **diarios a las 01:00** (`base/backup-YYYYMMDD-*`, retención ~7 días) + `wal_archive/` → backup físico continuo con WAL/PITR de la instancia Postgres, que **incluye la DB facturascripts**. Aun así, el AC#3 exige un `pg_dump` **lógico** puntual justo antes del upgrade (restaurable en una copia para el test), guardado en ese mismo `/cold-data/postgres-backups/`.
- **Rollback**: revert del PR + restore de la DB desde el dump tomado antes de mergear.

### Estado real verificado en el clúster (2026-06-27)
- **Pod**: `facturascripts-6d9d9546bd-dk7fs` (nodo `nixos`, label `name=facturascripts`), imagen `2025.81`, PHP 8.4.17.
- **DB**: **PostgreSQL 17.6** (pod `postgres-0` en `databases`). Base `facturascripts` de **15 MB, 89 tablas**, 19 facturas de cliente, 3 de proveedor, 6 clientes, 3 proveedores. Es pequeña → el `pg_dump` es cuestión de segundos y un test en copia es barato.
- **Plugins activos reales** (corrige el ticket original: *no* están instalados "Servicios" ni "Facturación Base" — esta última está integrada en el core desde 2018). Tras analizar el código de cada uno contra los tags `v2025.81` y `v2026.3`:
  1. **Verifactu** v0.84 — cumplimiento AEAT (Veri\*Factu), plugin oficial de facturascripts.com. Tablas `verifactu_registros_*` presentes pero **con 0 registros emitidos** → todavía no hay cadena de hash fiscal viva (riesgo de descuadre bajo hoy). 🔴 **La v0.84 (serie 2025) NO es compatible con 2026.x**: implementa `SalesLineModInterface`, extiende `FacturaCliente`/`LineaFacturaCliente`, usa `InvoiceOperation`/`OperacionIVA`/`RegimenIVA` (área refactorizada en 2026, ver abajo) y trae sus propias `MigrationClass`. **Acción obligatoria: instalar Verifactu v1.1** (compatible `2026.1–2026.3`, act. 24-06-2026) en el mismo paso que el core.
  2. **OIDC** v0.2 (custom propio, login con Authelia; el análisis original fue sobre v0.1, ya endurecido a v0.2 y desplegado — ver sección de deuda técnica) — si se rompe se pierde el SSO de acceso. 🟢 **Compatible con 2026.3**: ya usa la API nueva `Core\Where` y `extends Core\Controller\Login`, controlador estable en 2026.3 (solo añade un método protegido, sin romper firmas). Verificado que **no usa** ninguna constante del área de IVA que cambió.
  3. **Benefits** v0.2 (custom propio, dashboard P&L; análisis original sobre v0.1, ya endurecido a v0.2 y desplegado) — 🟢 **Compatible con 2026.3, con deuda técnica consciente**: mantiene API legacy (`Core\Base\Controller`) y SQL crudo, todo ello **aún presente y funcional en 2026.3** (solo `@deprecated`). No toca el área de IVA. Migración a `Core\Where`/`Core\Template\Controller` diferida a futuro antes de que se elimine la API legacy.

### Deuda técnica en NUESTROS plugins (OIDC, Benefits) — abordada 2026-07-12

Se han endurecido ambos plugins propios (bump `v0.1 → v0.2` en los dos) **antes** de promover el core, para no arrastrar los smells más sensibles al upgrade. Estado por ítem:

**OIDC** (v0.2 — commit `refactor(oidc): reuse core login session/cookies and delegate userinfo JWT verification to jumbojett`)
- ✅ **Sesión/cookies del core reusadas.** `OidcCallback` ahora `extends Core\Controller\Login` (antes `implements ControllerInterface`) y delega en `updateUserAndRedirect()` del core (`Session::set` + `newLogkey` + `saveCookies` + redirect). Eliminado el `loginUser()` reimplementado a mano. Solo se sobreescribe `saveCookies()` para contemplar `X-Forwarded-Proto` (el `isSecure()` del core da `false` tras el proxy con terminación TLS). Deja de divergir del endurecimiento de sesiones/2FA de 2026.
- ✅ **Verificación de JWT delegada en `jumbojett`.** Eliminados `decodeAndVerifyJwt()`, `rsaPublicKeyFromJwk()` y `derLength()` (parseo DER + `openssl_verify` a mano); ahora usa `$oidc->verifyJWTSignature()` de la librería vendorizada. Ya no hay criptografía de firma casera ni el fallback laxo del primer JWKS sin `kid`.
- ✅ **Superglobales → abstracción `Core\Request`.** `$_SERVER['HTTP_*']`/`HTTPS` sustituidos por `$request->header(...)`, `$request->host()`, `$request->isSecure()`; `createClient()`/`getCallbackUrl()` reciben el `Request`.
- ✅ **Logging unificado.** `error_log()` → `Tools::log('oidc')->error()` → los errores ya van a los canales de FS/Loki.
- 🟢 **Override de `/login`** vía `Kernel::addRoute`: se mantiene (funciona y el controlador `Login` es estable en 2026.3).

**Benefits** (v0.2)
- ✅ **Import muerto eliminado.** Borrado `use …\DataBaseWhere;` (y de paso el resto de `use` sin usar: `ControllerPermissions`, `Response`, `Tools`, `User`).
- 🟠 **SQL crudo: mantenido a propósito** (decisión consciente, tradeoff aceptado — **no** se migra al ORM). `queryMonthlyTotals()` conserva el `SELECT … SUM(neto) … GROUP BY` crudo por rendimiento (1 query vs. ~24 del ORM). Ahora está **documentado en el código** como punto frágil, con la alternativa ORM (`FacturaCliente::totalSum` + `Core\Where`) y verificado seguro en 2026.x (columnas `fecha`/`neto`/`idempresa` presentes e intactas en `Core/Table/*.xml`).
- 🟡 **Controlador base legacy: mantenido** (diferido). Sigue `extends Core\Base\Controller` con `privateCore(&$response, …)`; la API legacy sigue viva en 2026.3. Migración a `Core\Template\Controller` pospuesta.

> Con esto, la parte de hardening de plugins de esta tarea queda cerrada salvo lo diferido conscientemente (SQL crudo de Benefits y su controlador legacy). Lo pendiente es el upgrade del core en sí (ver Acceptance Criteria): bump a 2026.3, Verifactu v1.1, dumps y verificación fiscal.

### Migraciones que se ejecutarán al arrancar 2026.3

Hay **dos motores de migración** distintos que corren al hacer `/deploy`:

**1. Migraciones de schema del core (FacturaScripts).** El ORM sincroniza las tablas con los modelos de la versión nueva. En el major 2026 esto implica, entre otros, `ALTER TABLE` para:
- Campo "operación" en `clientes`/`proveedores` (intracomunitario / inversión de sujeto pasivo heredado a sus facturas).
- Guardado del estado previo de documentos al aprobarlos (para poder restaurarlo al eliminar).
- Refactor del área de IVA: nueva clase `TaxExceptions`, constantes de `RegimenIVA` deprecadas/eliminadas e `InvoiceOperation` ampliada (ver riesgos). Son cambios de código que pueden requerir reescritura de datos asociados a impuestos/regímenes.

Estas son **irreversibles** y se ejecutan sobre PostgreSQL (motor menos testeado por FS) → es el motivo del dump + test en copia.

**2. Migraciones del plugin Verifactu (mecanismo `MigrationClass`).** Verifactu corre sus propias migraciones registradas por nombre en `MyFiles/migrations.json` (no se repiten una vez aplicadas). Las de la **v0.84 instalada** ya se aplicaron; son **data-migrations idempotentes** (no `ALTER TABLE`), todas con guarda `tableExists()` y filtros `WHERE`, y en nuestra instalación son **no-ops porque las tablas `verifactu_*` tienen 0 registros**:

| Migración | Qué hace |
|---|---|
| `check_certificate` | Revalida el certificado de cada empresa. |
| `update_registro_evento_signature` / `update_registro_factura_signature` | Marca `signature=true` en registros cuyo JSON ya está firmado. |
| `update_registro_evento_status` | Pone `status=CORRECT` en eventos firmados sin estado. |
| `update_registro_factura_event` | Normaliza el campo `event` (`alta`/`subsanacion`/`anulacion` → constantes). |
| `remove_absolute_path_records` | Convierte rutas absolutas a relativas (`…/MyFiles/…`) y reordena carpetas `MyFiles/Verifactu<id>/` → `MyFiles/Verifactu/<id>/`. **Contempla PostgreSQL explícitamente** (`~` vs `REGEXP`). |

> **Verifactu v1.1 traerá su propio set de migraciones nuevas** (no auditadas aquí; su código está en `github.com/FacturaScripts/Verifactu`). Como hoy hay 0 registros emitidos, el riesgo de que una migración de datos del plugin corrompa una cadena fiscal viva es nulo; el riesgo real está en las migraciones de **schema del core**.

### Riesgos del salto (research del changelog 2025.81 → 2026.3)
2025.81 (27-ene-2026) es el último estable del ciclo 2025; **2026** (16-abr) es el major anual, 2026.1 (28-abr) un patch de UI, 2026.2 (13-may) fixes de widgets y **2026.3 (27-may)** la versión objetivo. Entre 2025.81 y 2026 solo hay betas no etiquetadas, consolidadas en el major.

- 🔴 **Rediseño del Calculator (motor de IVA).** Cambia el cálculo de bases/cuotas (intracomunitario, importación, exportación, inversión de sujeto pasivo). La interfaz `SalesLineModInterface` **no cambió** (estable entre 2025.81 y 2026.3), pero el área de IVA sí se refactorizó: `InvoiceOperation` ganó constantes/métodos (cambio mayormente aditivo; `BENEFIT_THIRD_PARTIES` cambió de valor) y **`RegimenIVA` introdujo `TaxExceptions`** con constantes deprecadas/eliminadas (`TAX_SYSTEM_SPECIAL_RETAIL_TRADERS`, `TAX_SYSTEM_TELECOM`, varias `ES_TAX_EXCEPTION_*`). Esto es justo lo que toca Verifactu → motivo por el que su v0.84 no vale y necesita la v1.1. Verificar además que las **19 facturas existentes** no cambian de importe y que las nuevas calculan bien.
- 🔴 **Migración de schema sobre PostgreSQL.** El major añade columnas (campo "operación" en clientes/proveedores, estado previo de documentos) y Verifactu v1.1 trae sus propias migraciones. FS está testeado oficialmente sobre **MySQL**; PostgreSQL recibe menos cobertura → no hay incidencias PG reportadas para 2026, pero "ausencia de evidencia ≠ evidencia de ausencia". Backup + revisión de logs de migración obligatorios.
- 🟡 **Verifactu v0.84 → v1.1.** Hay que reemplazar la carpeta del plugin por la build de la serie 2026. Riesgo: que la migración de datos del propio plugin (esquema `verifactu_*`) falle; mitigado por estar a 0 registros emitidos.
- 🟢 **OIDC y Benefits** (custom): compatibles con 2026.3 (verificado por análisis de código). `DataBaseWhere` sigue viva en 2026.3.
- 🟢 **PHP**: descartado, ya estamos en 8.4 (2026.3 exige 8.1). **config.php**: sin cambios documentados para 2026.
- ℹ️ **Seguridad**: 2025.81 ya incluye el fix de la SQLi crítica CVE-2026-25513 (GHSA-cjfx-qhwm-hf99); subir a 2026.3 lo mantiene y añade endurecimientos de 2FA/sesiones/uploads.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PR #75 (bump a 2026.1) cerrado y `lib/versions.json` apuntando a `2026.3` — commit `b20342b`, PR #75 CLOSED
- [x] #2 Build de Verifactu v1.1 (compatible 2026.1–2026.3) obtenida y desplegada en `/data/facturascripts/plugins/Verifactu`, reemplazando la v0.84 (owner uid 1000; v0.84 preservada en `/data/facturascripts/Verifactu.v084`, fuera del scan de plugins)
- [x] #3 `pg_dump` completo (lógico) de la base `facturascripts` (PostgreSQL) tomado justo antes del upgrade y guardado en `/cold-data/postgres-backups/` — `facturascripts-pre2026-20260712-1800.dump` (+ `-1750` del ensayo)
- [x] #4 Snapshot del hostPath `/data/facturascripts` realizado — `plugins-pre2026-20260712-1800.tgz` en `/cold-data/postgres-backups/` (captura Verifactu v0.84 + OIDC v0.2 + Benefits v0.2)
- [x] #5 Upgrade probado primero en una copia de la DB (`facturascripts_test`): core 2026.3 + Verifactu v1.1 arrancan, **89 tablas migradas sin errores** (0 fallos, logs FS+Loki limpios), `/deploy` responde 200. Copia y pod desechable eliminados tras el ensayo
- [x] #6 Tras promover, login OIDC con Authelia (passkey) funcionando y dashboard Benefits operativo (Ingresos 17.045 € = neto baseline)
- [x] #7 Las 33 facturas de cliente + 3 de proveedor **no cambian de importe** (diff exacto vs baseline; suma 15.654,80 €); Calculator verificado en detalle (FAC2026A1: Neto 1.200 + IGIC 7% 84 − IRPF 180 = 1.104 €). **Creación de factura de prueba nueva descartada por decisión del usuario** (evitar escribir en la contabilidad/cadena fiscal real; Calculator ya validado sobre las facturas existentes)
- [x] #8 Panel Verifactu **carga y compone** el informe tras el upgrade (tabs Buscar/Facturas/Eventos/Logs). **Emisión de registro descartada por decisión del usuario**: empresa en modo producción (`vf_debug_mode=false`) sin certificado ni entorno de pruebas AEAT → emitir iniciaría la cadena fiscal viva (hoy 0 registros), irreversible. Alcance limitado a carga/composición, tal como prevé el propio ticket
- [x] #9 Procedimiento de rollback documentado (ver Implementation Notes) y **verificado como viable**: el restore del dump se demostró al crear la copia del ensayo (Fase 2); el swap de plugins es reversible por rename
- [x] #10 Paseo funcional con Playwright: Dashboard, listado de facturas (33), detalle FAC2026A1, dashboard Benefits y panel Verifactu — **todas las páginas cargan sin errores**. Login por passkey hecho manualmente por el usuario; Playwright reutilizó la sesión autenticada
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Ejecución **secuencial fase a fase**: implementa una fase, para, verifica su checkpoint, y solo entonces sigue. Las Fases 2 y 3 son las únicas con despliegue. El GO/NO-GO real está en el checkpoint de la Fase 2 (ensayo en copia).

Prerequisitos:
- Túnel SSH abierto (`pgrep -f '6443:localhost:6443' >/dev/null || ssh -fN -L 6443:localhost:6443 nas`).
- Confirmar que `ssh nas 'sudo -n true'` no pide contraseña (varias fases usan `sudo` remoto para `tar`/`chown`; si pidiera password, colgaría).
- **Técnica recurrente (Fases 3 y 5)**: para parar/reemplazar el pod sin que ArgoCD lo revierta, hay que **suspender el auto-sync** de la Application primero, porque `selfHeal: true` revierte cualquier `replicas: 0` o drift en segundos:
  ```bash
  argocd app set facturascripts --sync-policy none --grpc-web     # suspender
  # ... operación ...
  argocd app set facturascripts --sync-policy automated --grpc-web # reactivar (vuelve a prune+selfHeal)
  ```

### Fase 0 — Preparación y línea base (sin deploy)

1. **Verificar nombres de columna** antes de construir el baseline (no dar por hecho `total`):
   ```bash
   kubectl exec -n databases postgres-0 -- psql -At facturascripts \
     -c "SELECT column_name FROM information_schema.columns WHERE table_name='facturascli' AND column_name IN ('codigo','total','neto')"
   ```
2. **Baseline de importes** (para AC#7). Exportar a fichero local los totales actuales, sin tocar nada:
   ```bash
   kubectl exec -n databases postgres-0 -- psql -At facturascripts \
     -c "SELECT codigo,total FROM facturascli ORDER BY codigo" > /tmp/fs-baseline-cli.txt
   kubectl exec -n databases postgres-0 -- psql -At facturascripts \
     -c "SELECT codigo,total FROM facturasprov ORDER BY codigo" > /tmp/fs-baseline-prov.txt
   ```
3. **SOAP en 2026.3**: ✅ ya verificado presente (2026-07-12) en la imagen `2026.3` y en la `2025.81` actual. Comando de referencia si se quiere reconfirmar:
   ```bash
   kubectl run fs-soapcheck-$(date +%s) --rm -i --restart=Never -n business \
     --image=docker.io/facturascripts/facturascripts:2026.3 --command -- php -m | grep -i soap
   ```
4. **Revisar el presupuesto del startup probe** `/deploy` (`u.probes.withStartup.http` en `lib/utils`): en un major las migraciones pueden tardar minutos; si `failureThreshold * periodSeconds` es corto, k8s mataría el pod **a mitad de migración** en la Fase 3. Anotar los valores y, si son ajustados, subirlos temporalmente para el upgrade.
5. **Confirmar Verifactu v1.1 local** en `/Users/danielramos/Documents/repos/apps/facturascript/verifactu` (`facturascripts.ini`: `version = 1.1`).

**Checkpoint 0**: baseline con las 19 facturas cliente + 3 proveedor; SOAP presente en 2026.3; presupuesto del startup probe suficiente (o ajustado); Verifactu local en v1.1. **Definir aquí la tolerancia de importes**: el Calculator nuevo puede recalcular/redondear legítimamente → decidir qué diferencias son aceptables y cuáles son NO-GO, para que el diff de la Fase 2 no dé un falso negativo.

### Fase 1 — Backups / red de seguridad (sin deploy)

Fijar un sello de fecha **una sola vez** para toda la fase (evita el bug de `$(date)` reevaluado si se cruza medianoche):

```bash
STAMP=$(date +%Y%m%d-%H%M)
```

1. **`pg_dump` lógico** (peer-auth dentro del pod, no expone contraseña; escribe directo al HDD vía el mount `/backups → /cold-data/postgres-backups`):
   ```bash
   kubectl exec -n databases postgres-0 -- \
     pg_dump -Fc -f /backups/facturascripts-pre2026-$STAMP.dump facturascripts
   # verificar que el dump es íntegro (lista el TOC sin restaurar):
   kubectl exec -n databases postgres-0 -- \
     pg_restore --list /backups/facturascripts-pre2026-$STAMP.dump | head
   ```
2. **Snapshot de plugins** (línea base de rollback, AC#4). `/data` no está bajo snapper → copia manual con perms (con `sudo` remoto, ya validado en prerequisitos):
   ```bash
   ssh nas "sudo tar czf /cold-data/postgres-backups/plugins-pre2026-$STAMP.tgz -C /data/facturascripts plugins"
   ssh nas "tar tzf /cold-data/postgres-backups/plugins-pre2026-$STAMP.tgz | head"
   ```
   > Alcance de AC#4: MyFiles ya tiene su rsync diario a `/cold-data/contabilidad`; el resto del estado de `/data/facturascripts` **es** la carpeta `plugins`, que es lo que captura este `.tgz`. No hay estado adicional relevante fuera de eso.

**Checkpoint 1**: dump lista su TOC sin error (restaurable) y el `.tgz` de plugins contiene `Verifactu`/`OIDC`/`Benefits`. Esto además **demuestra la viabilidad del restore** para AC#9.

### Fase 2 — Ensayo en copia de la DB (deploy throwaway, FUERA de ArgoCD)

Objetivo: probar core 2026.3 + Verifactu v1.1 contra una **copia** de la DB, sin tocar producción. El pod de ensayo se crea con `kubectl apply` (no está en git → ninguna Application lo gestiona → `prune`/`selfHeal` no lo tocan). No lleva `app: facturascripts` ni IngressRoute.

1. **DB copia** a partir del dump de la Fase 1 (el `CREATE`/`pg_restore` corren como superusuario `postgres` vía peer/trust; `--no-owner --role=facturascripts` evita divergencias de ownership y `set -e`/exit code detecta fallos reales):
   ```bash
   DUMP=/backups/facturascripts-pre2026-$STAMP.dump   # mismo STAMP de la Fase 1
   kubectl exec -n databases postgres-0 -- psql -v ON_ERROR_STOP=1 \
     -c "CREATE DATABASE facturascripts_test OWNER facturascripts TEMPLATE template0"
   kubectl exec -n databases postgres-0 -- \
     pg_restore --no-owner --role=facturascripts --exit-on-error -d facturascripts_test "$DUMP"
   echo "pg_restore exit=$?"   # debe ser 0
   ```
2. **Plugins/MyFiles de ensayo** en dirs temporales del NAS (no tocan los de prod), con Verifactu v1.1 sustituido y **ownership uid 1000** (el pod corre como `#1000`; si los ficheros quedan con otro owner, Verifactu no podrá escribir sus certificados/logs):
   ```bash
   ssh nas 'sudo cp -a /data/facturascripts/plugins /data/facturascripts/plugins-test'
   ssh nas 'sudo cp -a /data/facturascripts/myfiles /data/facturascripts/myfiles-test'
   # los *-test se crean como root (cp con sudo) → el rsync remoto necesita sudo para escribir dentro
   rsync -a --delete --exclude='.git/' --rsync-path='sudo rsync' \
     /Users/danielramos/Documents/repos/apps/facturascript/verifactu/ \
     nas:/data/facturascripts/plugins-test/Verifactu/
   ssh nas 'sudo chown -R 1000:1000 /data/facturascripts/plugins-test /data/facturascripts/myfiles-test'
   ```
3. **Manifiesto throwaway** `/tmp/fs-test.yaml`. Ojo: en `facturascripts.config.php` el `FS_DB_NAME` es un **literal** (`facturascripts`), no una variable → para apuntar a la copia hay que **materializar un config.php propio** en un ConfigMap (con `FS_DB_NAME='facturascripts_test'` y conservando `${FS_DB_PASS}` para envsubst). `FS_DB_PASS` se inyecta al init `render-config` por `secretKeyRef` del Secret existente `facturascripts-db` — **nunca `value:` en claro**. Estructura (mismo patrón que prod: init envsubst → emptyDir → contenedor principal):
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata: { name: facturascripts-test-config, namespace: business }
   data:
     config.php: |
       <?php
       define('FS_DB_TYPE', 'postgresql');
       define('FS_DB_HOST', 'postgres.databases.svc.cluster.local');
       define('FS_DB_PORT', 5432);
       define('FS_DB_NAME', 'facturascripts_test');   # <-- única diferencia real vs prod
       define('FS_DB_USER', 'facturascripts');
       define('FS_DB_PASS', '${FS_DB_PASS}');
       define('FS_LANG', 'es_ES'); define('FS_TIMEZONE', 'Atlantic/Canary');
       define('FS_DEBUG', false); define('FS_COOKIES_EXPIRE', 31536000);
       define('FS_ROUTE', ''); define('FS_DB_FOREIGN_KEYS', true); define('FS_DB_TYPE_CHECK', true);
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata: { name: facturascripts-test, namespace: business }   # sin label app: facturascripts
   spec:
     replicas: 1
     selector: { matchLabels: { name: facturascripts-test } }
     template:
       metadata: { labels: { name: facturascripts-test } }
       spec:
         securityContext: { runAsUser: 1000, runAsGroup: 1000 }
         initContainers:
           - name: render-config
             image: <misma imagen envsubst que versions.json>
             command: ['sh','-c','envsubst < /mnt/config-template/config.php > /mnt/config/config.php']
             env:
               - name: FS_DB_PASS
                 valueFrom: { secretKeyRef: { name: facturascripts-db, key: FS_DB_PASS } }
             volumeMounts:
               - { name: config-template, mountPath: /mnt/config-template }
               - { name: config-output, mountPath: /mnt/config }
         containers:
           - name: facturascripts
             image: docker.io/facturascripts/facturascripts:2026.3
             command: ['bash','-c','if [ ! -f /var/www/html/.htaccess ]; then cp -r /usr/src/facturascripts/* /var/www/html/; cp /var/www/html/htaccess-sample /var/www/html/.htaccess; chmod -R o+w /var/www/html; fi; exec apache2-foreground']
             ports: [ { containerPort: 80 } ]
             volumeMounts:
               - { name: config-output, mountPath: /var/www/html/config.php, subPath: config.php }
               - { name: plugins, mountPath: /var/www/html/Plugins }
               - { name: myfiles, mountPath: /var/www/html/MyFiles }
         volumes:
           - { name: config-output, emptyDir: {} }
           - { name: config-template, configMap: { name: facturascripts-test-config } }
           - { name: plugins, hostPath: { path: /data/facturascripts/plugins-test } }
           - { name: myfiles, hostPath: { path: /data/facturascripts/myfiles-test } }
   ```
   Aplicar: `kubectl apply -f /tmp/fs-test.yaml`. (Sin startup probe a propósito: así el pod queda `Ready` aunque `/deploy` tarde, y se observa la migración por logs sin que k8s lo mate.)
4. **Arrancar migraciones**: forzar el `/deploy` una vez el pod está `Running`:
   ```bash
   kubectl port-forward -n business deploy/facturascripts-test 8080:80 &
   curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8080/deploy
   ```
5. **Verificar el checkpoint**: migraciones en Loki `{namespace="business", pod=~"facturascripts-test.*"} |~ "(?i)error|migrat|deploy|fatal"`; y diff de importes en la copia (aplicando la tolerancia definida en Checkpoint 0):
   ```bash
   kubectl exec -n databases postgres-0 -- psql -At facturascripts_test \
     -c "SELECT codigo,total FROM facturascli ORDER BY codigo" | diff - /tmp/fs-baseline-cli.txt
   ```
6. **Teardown del ensayo** (siempre, pase o falle; `FORCE` corta conexiones vivas):
   ```bash
   kubectl delete -f /tmp/fs-test.yaml
   kubectl exec -n databases postgres-0 -- psql -c "DROP DATABASE facturascripts_test WITH (FORCE)"
   ssh nas 'sudo rm -rf /data/facturascripts/plugins-test /data/facturascripts/myfiles-test'
   ```

**Checkpoint 2 (GO/NO-GO)**: migraciones aplicadas sin error en Loki, `/deploy` responde 200, y los importes de la copia coinciden con la baseline **dentro de la tolerancia definida**. Si algo falla aquí, se corrige antes de tocar producción.

### Fase 3 — Promoción a producción (deploy real: rsync + GitOps)

Se hace con el pod **parado** para evitar la ventana en la que el core 2025.81 conviviría con el código v1.1 (o el 2026.3 con v0.84): ambas combinaciones son incompatibles. Al parar el pod durante el swap y traer uno nuevo ya con 2026.3 + v1.1, no hay convivencia. Requiere **suspender el auto-sync** (si no, `selfHeal` revierte el `replicas: 0`).

```bash
STAMP=$(date +%Y%m%d-%H%M)
```

1. **Dump + tar frescos** (repetir Fase 1 con `$STAMP` nuevo; captura cambios desde el ensayo).
2. **Suspender auto-sync y parar el pod**:
   ```bash
   argocd app set facturascripts --sync-policy none --grpc-web
   kubectl scale deploy/facturascripts -n business --replicas=0
   kubectl wait --for=delete pod -l name=facturascripts -n business --timeout=120s
   ```
3. **Swap de Verifactu v1.1 en prod** con rename dentro del mismo FS + ownership uid 1000 (con el pod ya parado no hay riesgo de carga parcial ni de convivencia de versiones):
   ```bash
   rsync -a --delete --exclude='.git/' --rsync-path='sudo rsync' \
     /Users/danielramos/Documents/repos/apps/facturascript/verifactu/ \
     nas:/data/facturascripts/Verifactu.new/
   ssh nas 'sudo mv /data/facturascripts/plugins/Verifactu /data/facturascripts/plugins/Verifactu.v084 && \
            sudo mv /data/facturascripts/Verifactu.new     /data/facturascripts/plugins/Verifactu && \
            sudo chown -R 1000:1000 /data/facturascripts/plugins/Verifactu'
   ```
4. **Bump del core**: editar `lib/versions.json` → `facturascripts.version: "2026.3"`.
5. **Desplegar** con la skill `/deploy` (commit + push a main; la CI exporta a la rama `manifests`).
6. **Reactivar auto-sync** → ArgoCD aplica el nuevo Deployment (imagen `2026.3`, `replicas: 1`) y arranca un pod nuevo con Verifactu v1.1 **activa**, que corre las migraciones al hacer `/deploy`:
   ```bash
   argocd app set facturascripts --sync-policy automated --grpc-web
   ```
7. **Cerrar el PR #75** de Renovate (AC#1).

**Checkpoint 3**: en Loki (`{namespace="business", pod=~"facturascripts.*"}`) las migraciones de core + Verifactu v1.1 sin error, el startup probe `/deploy` pasa y el pod queda `Ready` con imagen `2026.3`. Si el pod entra en CrashLoop o el probe no pasa → rollback (Fase 5).

### Fase 4 — Verificación funcional post-upgrade (sin deploy)

1. **Login OIDC** con Authelia (passkey, huella manual) → sesión OK (AC#6).
2. **Dashboard Benefits** carga y muestra cifras (AC#6).
3. **Importes**: las 19 facturas de cliente mantienen su total vs baseline dentro de la tolerancia (AC#7); crear una **factura de prueba** y validar que el Calculator nuevo calcula el IVA correcto. **Anular/borrar la factura de prueba** al terminar para no dejar un documento espurio en la contabilidad real.
4. **Verifactu** (AC#8): **confirmar primero que el plugin apunta al entorno de *pruebas* de la AEAT**, no a producción — emitir un registro real iniciaría la cadena de hash fiscal viva (hoy 0 registros) de forma irreversible. Con el entorno de pruebas confirmado, generar un registro de prueba a partir de los importes nuevos y comprobar que sale correcto. Si no hay entorno de pruebas disponible, limitar AC#8 a validar que el plugin **carga y compone** el registro sin emitirlo.
5. **Paseo Playwright** (AC#10): tras el login manual con passkey, reutilizar la sesión (`storageState`/CDP) y recorrer facturas, Benefits y panel Verifactu comprobando que cargan sin errores.

**Checkpoint 4**: AC#6, #7, #8 y #10 en verde; factura de prueba anulada.

### Fase 5 — Cierre y limpieza (sin deploy)

1. **Documentar el rollback verificado** (AC#9). Clave: **suspender el auto-sync antes de tocar réplicas/DB** (si no, `selfHeal` revierte el `replicas: 0` y no se puede parar FS para restaurar). Procedimiento:
   ```bash
   argocd app set facturascripts --sync-policy none --grpc-web        # imprescindible primero
   kubectl scale deploy/facturascripts -n business --replicas=0
   kubectl wait --for=delete pod -l name=facturascripts -n business --timeout=120s
   # Plugins: volver a v0.84
   ssh nas 'rm -rf /data/facturascripts/plugins/Verifactu && \
            mv /data/facturascripts/plugins/Verifactu.v084 /data/facturascripts/plugins/Verifactu'
   # DB: restaurar el dump (FORCE corta conexiones residuales)
   kubectl exec -n databases postgres-0 -- psql -v ON_ERROR_STOP=1 \
     -c "DROP DATABASE facturascripts WITH (FORCE)" \
     -c "CREATE DATABASE facturascripts OWNER facturascripts TEMPLATE template0"
   kubectl exec -n databases postgres-0 -- \
     pg_restore --no-owner --role=facturascripts --exit-on-error -d facturascripts /backups/<dump-fresco>
   # Core: revertir la versión y reactivar sync (trae el pod 2025.81 contra el schema restaurado)
   git revert <commit-bump> && git push        # o /deploy con la versión anterior
   argocd app set facturascripts --sync-policy automated --grpc-web
   ```
   > El `git revert` de la imagen **por sí solo no basta**: las migraciones de schema 2026 son irreversibles, así que el 2025.81 debe correr contra el **schema restaurado del dump**, no contra el schema ya migrado. Por eso el restore de DB y el revert van juntos, con el pod parado. Viabilidad ya demostrada por el restore de la Fase 1 + el ensayo de la Fase 2.
2. **Limpieza** tras un periodo de gracia (p. ej. 1 semana estable): borrar `Verifactu.v084` del hostPath. Conservar dump y `.tgz` en `/cold-data/postgres-backups/`.

**Checkpoint 5**: procedimiento de rollback escrito y validado; artefactos temporales limpios; tarea lista para revisión del usuario.
<!-- SECTION:PLAN:END -->

## Implementation Notes (ejecución 2026-07-12)

### Resultado
Upgrade `2025.81 → 2026.3` promovido a producción. Pod `facturascripts-6bfd8fdc7` con imagen `2026.3`, 0 restarts. Verifactu v1.1 + OIDC v0.2 + Benefits v0.2, todos `enabled`+`compatible`. 89 tablas migradas (55 cambios de schema: 29 columnas nuevas, 10 defaults, 9 constraints, 5 tipos, 2 drops), 0 fallos. Importes de las 36 facturas idénticos al baseline. Ventana de indisponibilidad ~4 min.

### ⚠️ Gotcha crítico: el startup probe `/deploy` NO dispara las migraciones
En un swap de imagen (vs. el botón "Actualizar" del admin), el arranque del pod deja `/deploy`→200 y el pod `Ready`, **pero no ejecuta `Core\Migrations::run()`** (las data-migrations fiscales) ni el chequeo de estructura de todas las tablas — eso solo lo hace `Updater::postUpdateAction()` (acción de admin). El schema se migra perezosamente por-modelo al navegar, con `FS_DEBUG=false` cacheado. **Hay que forzar la migración a mano** tras el deploy, replicando `postUpdateAction`:
```php
// php dentro del pod: bootstrap kernel + config, luego:
Plugins::init();
Plugins::deploy(true, true);   // migraciones de plugin (Verifactu)
Migrations::run();             // data-migrations del core (fixClientesOperation, fixTaxException)
DbUpdater::rebuild();          // resetea cache; luego createOrUpdateTable() por cada Core/Table + Plugins/*/Table *.xml
```
Para futuros upgrades del core: repetir este paso tras `/deploy`.

### Rollback verificado (AC#9)
Viabilidad demostrada: el restore del dump se usó para crear la copia del ensayo (Fase 2) y el swap de plugins es un simple rename. Procedimiento (con el pod parado, **suspendiendo antes el auto-sync** o `selfHeal` revierte el `replicas:0`):
```bash
argocd app set facturascripts --sync-policy none --grpc-web
kubectl scale deploy/facturascripts -n business --replicas=0
kubectl wait --for=delete pod -l name=facturascripts -n business --timeout=120s
# Plugins: volver a v0.84
ssh nas 'rm -rf /data/facturascripts/plugins/Verifactu && \
         cp -a /data/facturascripts/Verifactu.v084 /data/facturascripts/plugins/Verifactu && \
         sudo chown -R 1000:1000 /data/facturascripts/plugins/Verifactu'
# DB: restaurar el dump pre-upgrade (FORCE corta conexiones)
kubectl exec -n databases postgres-0 -- psql -U postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE facturascripts WITH (FORCE)" \
  -c "CREATE DATABASE facturascripts OWNER facturascripts TEMPLATE template0"
kubectl exec -n databases postgres-0 -- \
  pg_restore -U postgres --no-owner --role=facturascripts --exit-on-error \
  -d facturascripts /backups/facturascripts-pre2026-20260712-1800.dump
# Core: revertir versión y reactivar sync
git revert b20342b && git push
argocd app set facturascripts --sync-policy automated --grpc-web
```
El `git revert` por sí solo no basta: las migraciones de schema 2026 son irreversibles, así que el 2025.81 debe correr contra el **schema restaurado del dump**.

### Backups / artefactos de rollback (en `/cold-data/postgres-backups/`)
- `facturascripts-pre2026-20260712-1800.dump` (dump lógico pre-upgrade de prod) + `-1750` (ensayo).
- `plugins-pre2026-20260712-1800.tgz` (+ `-1750`).
- `/data/facturascripts/Verifactu.v084` (carpeta del plugin v0.84).
- **Limpieza diferida** (tras ~1 semana estable): borrar `Verifactu.v084`; conservar dumps y `.tgz`.

### Descartado por decisión del usuario
- AC#7 factura de prueba nueva y AC#8 emisión de registro Verifactu: no se ejecutan para no escribir en la contabilidad/cadena fiscal real (empresa en modo producción `vf_debug_mode=false`, sin certificado ni entorno de pruebas AEAT; 0 registros hoy). El Calculator quedó validado sobre las facturas existentes.
