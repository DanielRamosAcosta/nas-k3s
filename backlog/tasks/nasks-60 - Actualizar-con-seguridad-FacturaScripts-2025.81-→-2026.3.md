---
id: NASKS-60
title: 'Actualizar con seguridad FacturaScripts 2025.81 → 2026.3'
status: To Do
assignee: []
created_date: '2026-05-07 20:44'
updated_date: '2026-06-27 00:00'
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
  - 'https://github.com/NeoRazorX/facturascripts/security/advisories/GHSA-cjfx-qhwm-hf99'
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
- **Plugin Verifactu**: vive en hostPath `/data/facturascripts/plugins/Verifactu` (no en la imagen). Hay que **reemplazar la carpeta por la build v1.1** (compatible 2026.1–2026.3) antes/durante el upgrade; ahora su código es público en `github.com/FacturaScripts/Verifactu`. Confirmar si la instalación sigue requiriendo suscripción de facturascripts.com o ya es libre.
- **Migraciones**: FS las aplica al arrancar contra `/deploy`, que es el startup probe (`facturascripts.libsonnet:38`). En majors puede tardar varios minutos y son **irreversibles** sin dump previo. El changelog de migraciones queda en `MyFiles/{migrations.json,db-changelog.json,db-updater.json}`.
- **MyFiles**: hostPath `/data/facturascripts/myfiles` con rsync diario a `/cold-data/contabilidad` (cron `0 3 * * *`). El resto de `/data/facturascripts` (plugins + estado) **no** tiene esa copia.
- **DB**: no existe backup automatizado de la DB de FacturaScripts en este repo (caso análogo a NASKS-59 / VictoriaMetrics). Conviene valorar una tarea separada para automatizar dumps periódicos.
- **Rollback**: revert del PR + restore de la DB desde el dump tomado antes de mergear.

### Estado real verificado en el clúster (2026-06-27)
- **Pod**: `facturascripts-6d9d9546bd-dk7fs` (nodo `nixos`, label `name=facturascripts`), imagen `2025.81`, PHP 8.4.17.
- **DB**: **PostgreSQL 17.6** (pod `postgres-0` en `databases`). Base `facturascripts` de **15 MB, 89 tablas**, 19 facturas de cliente, 3 de proveedor, 6 clientes, 3 proveedores. Es pequeña → el `pg_dump` es cuestión de segundos y un test en copia es barato.
- **Plugins activos reales** (corrige el ticket original: *no* están instalados "Servicios" ni "Facturación Base" — esta última está integrada en el core desde 2018). Tras analizar el código de cada uno contra los tags `v2025.81` y `v2026.3`:
  1. **Verifactu** v0.84 — cumplimiento AEAT (Veri\*Factu), plugin oficial de facturascripts.com. Tablas `verifactu_registros_*` presentes pero **con 0 registros emitidos** → todavía no hay cadena de hash fiscal viva (riesgo de descuadre bajo hoy). 🔴 **La v0.84 (serie 2025) NO es compatible con 2026.x**: implementa `SalesLineModInterface`, extiende `FacturaCliente`/`LineaFacturaCliente`, usa `InvoiceOperation`/`OperacionIVA`/`RegimenIVA` (área refactorizada en 2026, ver abajo) y trae sus propias `MigrationClass`. **Acción obligatoria: instalar Verifactu v1.1** (compatible `2026.1–2026.3`, act. 24-06-2026) en el mismo paso que el core.
  2. **OIDC** v0.1 (custom propio, login con Authelia) — si se rompe se pierde el SSO de acceso. 🟢 **Compatible con 2026.3**: ya usa la API nueva `Core\Where` y `extends Core\Controller\Login`, controlador estable en 2026.3 (solo añade un método protegido, sin romper firmas). Verificado que **no usa** ninguna constante del área de IVA que cambió.
  3. **Benefits** v0.1 (custom propio, dashboard P&L) — 🟢 **Compatible con 2026.3, con deuda técnica**: usa API legacy (`Core\Base\Controller`, `ControllerPermissions`, `DataBaseWhere`), todo ello **aún presente y funcional en 2026.3** (solo `@deprecated`). No toca el área de IVA. Conviene migrar a `Core\Where` a futuro antes de que se elimine la API legacy.

### Malos usos / deuda técnica en NUESTROS plugins (OIDC, Benefits)

Revisión del código de los dos plugins propios. Ninguno **bloquea** el upgrade (ambos son 🟢 compatibles), pero son los puntos frágiles donde podrían romperse a futuro o que conviene endurecer. Ordenados por relevancia para 2026.3:

**OIDC**
- 🟠 **Duplica la lógica de sesión/cookies del core.** `OidcCallback::loginUser()`/`saveCookies()` reimplementan a mano `Session::set('user')`, `newLogkey()` y las cookies `fsNick`/`fsLogkey`/`fsLang` porque `OidcCallback` implementa `ControllerInterface` (no extiende `Login`) y no puede reusar el método `protected` del core. **2026 endurece sesiones/2FA** → esta copia puede divergir del core; es el smell más sensible al upgrade. Verificar el login tras subir.
- 🟠 **Verificación de JWT hecha a mano** (`decodeAndVerifyJwt`: parseo base64url, `alg`, descarga de JWKS, `openssl_verify`) **teniendo ya `jumbojett/openid-connect-php` vendorizado** para eso. Reinventar criptografía de firma es riesgo de seguridad; debería delegarse en la librería. Además, si el JWT no trae `kid` coge la primera clave del JWKS (laxo).
- 🟡 **Acceso directo a superglobales** (`$_SERVER['HTTP_USER_AGENT']`, `HTTP_X_FORWARDED_PROTO`, `HTTPS`) en vez de la abstracción `Request`/`Http` del core, que el propio plugin ya usa en otros sitios → inconsistente y frágil detrás de proxy.
- 🟡 **Logging mixto**: usa `error_log()` directo en algunos catch en vez de `Tools::log()` (que sí emplea en el resto) → esos errores no van a los canales de FS/Loki.
- 🟢 **Override de la ruta `/login`** vía `Kernel::addRoute` apuntando a su subclase: funciona y el controlador `Login` es estable en 2026.3, pero acopla al sistema de rutas del core.

**Benefits**
- 🟠 **SQL crudo bypaseando el ORM**: `queryMonthlyTotals()` arma a mano `SELECT EXTRACT(YEAR FROM fecha) … SUM(neto) … GROUP BY` sobre `facturascli`/`facturasprov`. Usa `var2str()` (sin riesgo de SQLi), pero **acopla a nombres de tabla/columna del schema** (`fecha`, `neto`, `idempresa`) justo en un major que **refactoriza el área fiscal** → es lo que más podría romperse silenciosamente. Lo idóneo: usar los modelos `FacturaCliente`/`FacturaProveedor` y agregación del core.
- 🟡 **Import muerto de API deprecada**: declara `use …\DataBaseWhere;` pero **nunca lo instancia** (es la única "ocurrencia" que detectó el grep). Dependencia innecesaria de una clase `@deprecated`; basta con borrar el `use`.
- 🟡 **Controlador base legacy**: `extends Core\Base\Controller` con firma antigua `privateCore(&$response, $user, $permissions)` y `->all([], …)`. Migrar al controlador moderno (`Core\Template\Controller` + `Core\Where`).

> Esta deuda no es parte del DoD de este upgrade, pero justifica un ticket de hardening posterior (sobre todo: que OIDC delegue sesión/cookies y verificación JWT en el core/librería, y que Benefits deje de leer tablas fiscales con SQL crudo).

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
- [ ] #1 PR #75 (bump a 2026.1) cerrado y `lib/versions.json` apuntando a `2026.3`
- [ ] #2 Build de Verifactu v1.1 (compatible 2026.1–2026.3) obtenida y desplegada en `/data/facturascripts/plugins/Verifactu`, reemplazando la v0.84
- [ ] #3 `pg_dump` completo de la base `facturascripts` (PostgreSQL) tomado justo antes del upgrade
- [ ] #4 Snapshot del hostPath `/data/facturascripts` (plugins + estado fuera de MyFiles) realizado
- [ ] #5 Upgrade probado primero en una copia de la DB: core 2026.3 + Verifactu v1.1 arrancan, migraciones aplicadas sin errores (logs de migración revisados vía Loki) y `/deploy` pasa
- [ ] #6 Tras promover, login OIDC con Authelia funcionando y dashboard Benefits operativo
- [ ] #7 Factura de cliente de prueba validada con el Calculator nuevo (IVA correcto) y revisión de que las 19 facturas existentes no cambian de importe
- [ ] #8 Verifactu operativo tras el upgrade (capaz de generar registro AEAT correcto a partir de los importes nuevos)
- [ ] #9 Procedimiento de rollback (revert versión + restore DB desde el dump + restaurar carpeta de plugins) documentado y verificado como viable
<!-- AC:END -->
