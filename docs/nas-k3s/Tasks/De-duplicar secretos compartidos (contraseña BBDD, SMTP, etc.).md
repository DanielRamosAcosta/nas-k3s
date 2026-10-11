---
title: 'De-duplicar secretos compartidos (contraseña BBDD, SMTP, etc.)'
status: Done
created_date: '2026-03-20 08:09'
labels:
  - refactor
dependencies: []
references:
  - lib/media/immich/immich.secrets.json
  - lib/media/invidious/invidious.secrets.json
priority: 3
ordinal: 0.244140625
---

## Description

Varios servicios usan los mismos secretos (ej: contraseña de PostgreSQL, credenciales SMTP) pero cada uno los encripta por separado en su propio SealedSecret. Esto significa que rotar un secreto compartido requiere re-encriptar en múltiples sitios.

Investigar si se puede centralizar estos secretos en un único SealedSecret cluster-wide y referenciarlos desde cada servicio.
