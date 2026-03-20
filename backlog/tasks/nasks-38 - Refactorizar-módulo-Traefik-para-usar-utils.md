---
id: NASKS-38
title: Refactorizar módulo Traefik para usar utils
status: In Progress
assignee: []
created_date: '2026-03-19 20:11'
updated_date: '2026-03-20 18:05'
labels:
  - refactor
dependencies: []
references:
  - lib/system/traefik/traefik.libsonnet
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
El módulo de Traefik (`lib/system/traefik/traefik.libsonnet`) tiene el mismo problema que ArgoCD: es un JSON grande sin usar las utilidades compartidas. Refactorizar para seguir el patrón estándar con helpers de utils.
<!-- SECTION:DESCRIPTION:END -->
