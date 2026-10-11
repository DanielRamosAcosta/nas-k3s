---
title: Refactorizar módulo ArgoCD para usar utils
status: Done
created_date: '2026-03-19 20:11'
labels:
  - refactor
dependencies: []
references:
  - lib/system/argocd/argocd.libsonnet
priority: 3
ordinal: 7.8125
---

## Description

El módulo de ArgoCD (`lib/system/argocd/argocd.libsonnet`) es básicamente un JSON grande sin usar las utilidades compartidas (`utils.libsonnet`). Refactorizar para usar los helpers de utils (labelApp, sealedSecret, configMap, etc.) y seguir el patrón estándar de los demás módulos.
