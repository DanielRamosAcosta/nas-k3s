---
id: NASKS-37
title: >-
  Refactorizar secrets de Immich: usar keys individuales en vez de JSON
  serializado
status: Done
assignee: []
created_date: '2026-03-19 20:11'
updated_date: '2026-03-20 18:05'
labels:
  - refactor
dependencies: []
references:
  - lib/media/immich/
priority: low
ordinal: 3.90625
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Los secrets de Immich parecen tener el JSON entero serializado en lugar de las keys individuales encriptadas por separado. Refactorizar para que cada secret key se encripte individualmente siguiendo el patrón estándar del proyecto.
<!-- SECTION:DESCRIPTION:END -->
