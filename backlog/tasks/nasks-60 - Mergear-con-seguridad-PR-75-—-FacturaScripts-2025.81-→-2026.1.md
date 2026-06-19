---
id: NASKS-60
title: 'Mergear con seguridad PR #75 — FacturaScripts 2025.81 → 2026.1'
status: To Do
assignee: []
created_date: '2026-05-07 20:44'
updated_date: '2026-06-19 16:56'
labels:
  - business
  - facturascripts
  - upgrade
dependencies: []
references:
  - 'https://github.com/DanielRamosAcosta/nas-k3s/pull/75'
  - 'https://github.com/NeoRazorX/facturascripts/releases/tag/v2026'
  - 'https://github.com/NeoRazorX/facturascripts/releases/tag/v2026.1'
  - lib/business/facturascripts/facturascripts.libsonnet
  - lib/versions.json
priority: medium
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Contexto

Renovate ha abierto PR #75 con un salto **mayor anual** de FacturaScripts (`2025.81` → `2026.1`). El diff en este repo es trivial (1 línea en `lib/versions.json`), pero el riesgo real está fuera del jsonnet:

- En **v2026** se rediseña el Calculator para soportar IVA intracomunitario, importación, exportación e inversión de sujeto pasivo → **el motor de cálculo de impuestos cambia**.
- FS aplica migraciones de schema **al arrancar contra `/deploy`**, que es justo el startup probe (`facturascripts.libsonnet:38`). No hay rollback limpio de schema sin dump previo.
- Plugins viven en hostPath `/data/facturascripts/plugins`. Suelen pinear `min_version`/`max_version` y romper en majors.
- MyFiles (`/data/facturascripts/myfiles`) sí tiene rsync diario a `/cold-data/contabilidad` (cron `0 3 * * *`).
- CI verde solo valida que el jsonnet compila — no dice nada de runtime.

## Plan propuesto

1. Listar plugins instalados en `/data/facturascripts/plugins` y comprobar compatibilidad con 2026.x (al menos `Servicios` y `Facturación Base`).
2. Hacer dump completo de la DB de FacturaScripts justo antes de mergear.
3. Snapshot del hostPath `/data/facturascripts` (plugins + estado fuera de MyFiles).
4. Mergear PR #75 en ventana de baja actividad.
5. Vigilar el startup probe `/deploy` — en majors puede tardar varios minutos en aplicar migraciones.
6. Validar con una factura de prueba que el Calculator nuevo no rompe el flujo habitual (especialmente IVA).
7. Si algo falla → revert PR + restore DB desde el dump.

## Notas

- No existe backup automatizado de la DB de FacturaScripts en este repo (ver NASKS-59 para el caso análogo de VictoriaMetrics). Quizás convenga abrir tarea separada para automatizar dumps periódicos de la DB de FS.
- El cambio fiscal del Calculator amerita revisión humana, no solo "que arranque".
<!-- SECTION:DESCRIPTION:END -->
