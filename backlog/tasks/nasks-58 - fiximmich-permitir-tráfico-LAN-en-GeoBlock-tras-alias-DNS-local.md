---
id: NASKS-58
title: 'fix(immich): permitir tráfico LAN en GeoBlock tras alias DNS local'
status: In Progress
assignee: []
created_date: '2026-04-23 09:28'
labels:
  - bug
  - immich
  - crowdsec
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tras introducir el alias DNS local `photos.danielramos.me → 192.168.1.200` (NASKS-52), las peticiones desde la LAN llegan a Traefik con la IP real privada (ej. 192.168.1.11). El middleware `immich-geoblock-es-cu` tiene `allowLocalRequests: false`, por lo que deniega esas peticiones con 403 antes de comprobar el país.

Log confirmatorio:
```
GeoBlock: media-immich-geoblock-es-cu@kubernetescrd: request denied [192.168.1.11] since local IP addresses are denied
```

Fix: `allowLocalRequests: true` en `lib/media/immich/immich.libsonnet`. El tráfico externo vía Cloudflare sigue trayendo IP pública real en X-Forwarded-For (trusted CF CIDRs + externalTrafficPolicy=Local), así que el bypass solo afecta a LAN/privadas.
<!-- SECTION:DESCRIPTION:END -->
