---
title: Añadir CI con GitHub Actions para validar manifiestos
status: Done
created_date: '2026-03-15 17:48'
labels:
  - ci
  - infrastructure
dependencies:
  - "[[Migrar a Sealed Secrets para poder usar secrets en CI]]"
priority: 2
ordinal: 125
---

## Description

Crear un GitHub Action que ejecute `tk eval` en todos los environments cuando se abre una PR. Esto valida que los manifiestos Jsonnet compilan correctamente antes de mergear.

Bloqueado por [[Migrar a Sealed Secrets para poder usar secrets en CI]] (migrar secrets) — sin acceso a secrets en CI, `tk eval` falla.

## Acceptance Criteria
- [ ] #1 `tk eval` se ejecuta en CI para los 6 environments (arr, media, monitoring, auth, databases, system)
- [ ] #2 PRs de Renovate se validan automáticamente
- [ ] #3 CI falla si un environment no compila

## Final Summary

CI con GitHub Actions implementada. Workflow validate.yml ejecuta tk eval en todos los environments en push a main y PRs. Usa kobtea/setup-jsonnet-action para jb + jsonnet, unfunco/setup-tanka para tk v0.36.2, y tk tool charts vendor para Helm charts. Los 7 environments validan correctamente.
