---
id: NASKS-77
title: Hardening del plugin Benefits de FacturaScripts
status: To Do
assignee: []
created_date: '2026-06-27 08:19'
labels:
  - business
  - facturascripts
  - benefits
  - tech-debt
dependencies:
  - NASKS-60
priority: low
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Reducir la deuda técnica del plugin propio Benefits (dashboard de pérdidas/ganancias) de FacturaScripts: dejar de leer las tablas fiscales con SQL crudo, eliminar un import muerto de API deprecada y migrar al controlador moderno. Detectado al auditar el plugin para el upgrade a 2026.3 (NASKS-60).

## 🎯 Contexto funcional

Benefits es un plugin custom (no del marketplace) que muestra un dashboard de ingresos vs. gastos por mes. Es de solo lectura y no crítico, pero su implementación se acopla directamente al schema de tablas fiscales con SQL crudo, justo el área que el major 2026 refactoriza → puede romperse de forma silenciosa en upgrades. El objetivo es alinearlo con la API del core (modelos + Where moderno) para que sea robusto ante cambios de schema y deje de depender de clases deprecadas.

## ⚙️ Contexto técnico

Plugin en hostPath `/data/facturascripts/plugins/Benefits` (solo `Controller/Benefits.php` + `Init.php`). Hallazgos del code-review (contra core `v2025.81`/`v2026.3`):

- **SQL crudo bypaseando el ORM**: `queryMonthlyTotals()` construye a mano `SELECT EXTRACT(YEAR FROM fecha) AS yr, EXTRACT(MONTH FROM fecha) AS mn, SUM(neto) AS total FROM facturascli/facturasprov WHERE … GROUP BY …`. Usa `var2str()` (sin riesgo de SQLi) pero se acopla a nombres de tabla/columna (`fecha`, `neto`, `idempresa`) → frágil ante el refactor fiscal de 2026. Sustituir por los modelos `FacturaCliente`/`FacturaProveedor` y la API de agregación del core.
- **Import muerto de API deprecada**: declara `use FacturaScripts\Core\Base\DataBase\DataBaseWhere;` pero **nunca lo instancia** (única ocurrencia detectada por grep). `DataBaseWhere` está `@deprecated` en 2026 → basta con borrar el `use`.
- **Controlador base legacy**: `class Benefits extends Core\Base\Controller` con firma antigua `privateCore(&$response, $user, $permissions)` y `(new Ejercicio())->all([], …)`. Migrar al controlador moderno (`Core\Template`/`Core\Controller`) y a `Core\Where`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 queryMonthlyTotals() deja de usar SQL crudo y usa los modelos del core (FacturaCliente/FacturaProveedor) o su API de agregación, sin acoplarse a nombres de columna del schema (neto, fecha, idempresa)
- [ ] #2 Se elimina el import muerto de DataBaseWhere
- [ ] #3 Se migra del controlador legacy Core\Base\Controller al moderno (Core\Template/Core\Controller) con Core\Where
- [ ] #4 El dashboard sigue mostrando los mismos datos (ingresos/gastos/beneficio mensual) tras los cambios
<!-- AC:END -->
