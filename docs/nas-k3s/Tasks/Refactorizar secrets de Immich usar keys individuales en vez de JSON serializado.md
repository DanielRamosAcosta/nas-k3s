---
title: >-
  Refactorizar secrets de Immich: usar keys individuales en vez de JSON
  serializado
status: Done
created_date: '2026-03-19 20:11'
labels:
  - refactor
dependencies: []
references:
  - lib/media/immich/
priority: 3
ordinal: 3.90625
---

## Description

Los secrets de Immich parecen tener el JSON entero serializado en lugar de las keys individuales encriptadas por separado. Refactorizar para que cada secret key se encripte individualmente siguiendo el patrón estándar del proyecto.
