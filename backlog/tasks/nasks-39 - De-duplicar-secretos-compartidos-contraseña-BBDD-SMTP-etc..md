---
id: NASKS-39
title: 'De-duplicar secretos compartidos (contraseña BBDD, SMTP, etc.)'
status: To Do
assignee: []
created_date: '2026-03-20 08:09'
updated_date: '2026-03-20 19:05'
labels:
  - refactor
dependencies: []
references:
  - lib/media/immich/immich.secrets.json
  - lib/media/invidious/invidious.secrets.json
priority: low
ordinal: 14875
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Varios servicios usan los mismos secretos (ej: contraseña de PostgreSQL, credenciales SMTP) pero cada uno los encripta por separado en su propio SealedSecret. Esto significa que rotar un secreto compartido requiere re-encriptar en múltiples sitios.

Investigar si se puede centralizar estos secretos en un único SealedSecret cluster-wide y referenciarlos desde cada servicio.
<!-- SECTION:DESCRIPTION:END -->
