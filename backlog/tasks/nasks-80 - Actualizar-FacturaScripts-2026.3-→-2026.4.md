---
id: NASKS-80
title: Actualizar FacturaScripts 2026.3 → 2026.4
status: Done
assignee: []
created_date: '2026-07-12 16:31'
updated_date: '2026-07-12 16:40'
labels:
  - business
  - facturascripts
  - upgrade
dependencies: []
references:
  - 'https://facturascripts.com/publicaciones/novedades-facturascripts-2026-4'
  - lib/versions.json
  - lib/business/facturascripts/facturascripts.libsonnet
priority: low
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Bump menor de FacturaScripts `2026.3` → `2026.4`. A diferencia de NASKS-60 (salto mayor anual), es un patch de bajo riesgo: sin migraciones de schema documentadas, sin cambios en el Calculator/IVA, sin ruptura de compatibilidad de plugins ni nuevos requisitos PHP. Verifactu se queda en v1.1 (no hay swap de plugin).

## 🎯 Contexto funcional

FacturaScripts (contabilidad/facturación del homelab, namespace `business`) ha publicado 2026.4 como continuación de la serie 2026. El usuario subió primero a 2026.3 (NASKS-60) como escalón y ahora quiere la 2026.4. Las novedades son incrementales (rendimiento/cachés, seguridad/control de propiedad, mejoras UX, corrección de contabilización de gastos bancarios). Publicada como BETA → conviene verificación funcional read-only tras el deploy.

## ⚙️ Contexto técnico

- **Diff**: 1 línea en `lib/versions.json` (`facturascripts.version: 2026.3 → 2026.4`). Tag `2026.4` confirmado en Docker Hub vía skopeo.
- **Despliegue**: GitOps normal — `/deploy` (commit+push a main → CI → rama manifests → ArgoCD auto-sync). Sin ensayo en copia ni swap de plugins (Verifactu v1.1 intacto).
- **Gotcha heredado de NASKS-60**: el startup probe `/deploy` NO dispara las migraciones. Aunque 2026.4 no documenta migraciones, tras el deploy hay que forzar `postUpdateAction` a mano (bootstrap kernel + `Plugins::deploy(true,true)` + `Migrations::run()` + barrido `DbUpdater`) por si hubiera algún ajuste de estructura, y revisar logs.
- **Verificación funcional SIN escrituras**: paseo Playwright (login OIDC por passkey manual, dashboard, listado/detalle de facturas, Benefits, panel Verifactu) comprobando que cargan sin errores. Confirmar que Verifactu v1.1 sigue `compatible` con 2026.4. No crear facturas ni emitir registros Verifactu.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `lib/versions.json` actualizado a `2026.4` y desplegado vía /deploy (ArgoCD Synced/Healthy, pod con imagen 2026.4, 0 restarts)
- [x] #2 Migraciones forzadas a mano tras el deploy (postUpdateAction) sin errores; logs FS/Loki limpios
- [x] #3 Verifactu v1.1 sigue enabled + compatible con 2026.4; OIDC y Benefits operativos
- [x] #4 Verificación funcional read-only con Playwright: dashboard, listado/detalle de facturas, Benefits y panel Verifactu cargan sin errores (login OIDC por passkey hecho manualmente por el usuario). Sin escrituras en la contabilidad ni emisión Verifactu
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bump `2026.3 → 2026.4` completado. `lib/versions.json` actualizado (commit `8203151`), CI verde, ArgoCD Synced/Healthy. Rolling update sin parar el pod: nuevo pod `facturascripts-5c7b5fcb56` con imagen 2026.4, Ready, 0 restarts.

Tras el deploy se forzó `postUpdateAction` a mano (gotcha de NASKS-60): `Plugins::deploy(true,true)` + `Migrations::run()` + barrido `DbUpdater` → 89 tablas, **0 cambios/0 fallos** (patch sin migraciones, como se esperaba). Logs FS/Loki limpios. Verifactu v1.1 sigue `enabled`+`compatible` con 2026.4; OIDC v0.2 y Benefits v0.2 operativos. Importes de las 33 facturas intactos (total 15.654,80 €).

Verificación funcional read-only con Playwright (login por SSO Authelia reutilizado): Dashboard, listado de facturas (33), Benefits (17.045 €) y panel Verifactu cargan sin errores. Sin escrituras en contabilidad ni emisión Verifactu.

Incidencia ajena al upgrade: durante la verificación se cayó el túnel SSH/VPN de admin (`vpn.danielramos.me:21873`) — pero los servicios públicos siguieron UP (facturas→302, Authelia→200, ArgoCD→200); no relacionado con el patch.
<!-- SECTION:FINAL_SUMMARY:END -->
