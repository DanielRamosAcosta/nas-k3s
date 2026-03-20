---
id: NASKS-36
title: Refactorizar módulo ArgoCD para usar utils
status: Done
assignee: []
created_date: '2026-03-19 20:11'
updated_date: '2026-03-20 18:05'
labels:
  - refactor
dependencies: []
references:
  - lib/system/argocd/argocd.libsonnet
priority: low
ordinal: 7.8125
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
El módulo de ArgoCD (`lib/system/argocd/argocd.libsonnet`) es básicamente un JSON grande sin usar las utilidades compartidas (`utils.libsonnet`). Refactorizar para usar los helpers de utils (labelApp, sealedSecret, configMap, etc.) y seguir el patrón estándar de los demás módulos.
<!-- SECTION:DESCRIPTION:END -->
