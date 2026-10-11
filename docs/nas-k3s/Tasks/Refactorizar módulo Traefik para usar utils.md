---
title: Refactorizar módulo Traefik para usar utils
status: Done
created_date: '2026-03-19 20:11'
labels:
  - refactor
dependencies: []
references:
  - lib/system/traefik/traefik.libsonnet
priority: 3
ordinal: 1.953125
---

## Description

El módulo de Traefik (`lib/system/traefik/traefik.libsonnet`) tiene el mismo problema que ArgoCD: es un JSON grande sin usar las utilidades compartidas. Refactorizar para seguir el patrón estándar con helpers de utils.
