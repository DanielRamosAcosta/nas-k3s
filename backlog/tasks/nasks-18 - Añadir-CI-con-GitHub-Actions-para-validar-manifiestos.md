---
id: NASKS-18
title: Añadir CI con GitHub Actions para validar manifiestos
status: To Do
assignee: []
created_date: '2026-03-15 17:48'
labels:
  - ci
  - infrastructure
dependencies:
  - NASKS-17
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Crear un GitHub Action que ejecute `tk eval` en todos los environments cuando se abre una PR. Esto valida que los manifiestos Jsonnet compilan correctamente antes de mergear.

Bloqueado por NASKS-17 (migrar secrets) — sin acceso a secrets en CI, `tk eval` falla.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `tk eval` se ejecuta en CI para los 6 environments (arr, media, monitoring, auth, databases, system)
- [ ] #2 PRs de Renovate se validan automáticamente
- [ ] #3 CI falla si un environment no compila
<!-- AC:END -->
