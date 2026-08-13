---
id: NASKS-86
title: >-
  Vanity metrics Tier 3 — exporters custom (wger, FacturaScripts, grimmory,
  jDownloader)
status: To Do
assignee: []
created_date: '2026-08-09 20:02'
updated_date: '2026-08-09 23:56'
labels: []
dependencies: []
references:
  - 'https://github.com/arturgoms/homelab'
  - 'https://wger.readthedocs.io/en/latest/api.html'
priority: low
type: feature
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Servicios del NAS que darían buenas "vanity metrics" pero **no tienen exporter oficial ni métricas Prometheus nativas** — requieren construir un exporter custom (Python + prometheus_client) que consulte su API REST (o BD). Se separan de NASKS-67 (que cubre los exporters nativos/comunidad ya disponibles: scraparr, immich-exporter, crowdsec, traefik, navidrome, mc-monitor, deluge).

## 🎯 Contexto funcional

Completar el "muro de vanity" con métricas personales/de negocio que hoy no son accesibles vía Prometheus. Cada servicio necesita un pequeño exporter a medida.

## ⚙️ Candidatos (Tier 3)

- **wger** (fitness, ns `business`) — workouts registrados, volumen total levantado, entradas de peso corporal, evolución. Tiene API REST documentada → exporter vía API. Alto valor "ego personal".
- **FacturaScripts** (ns `business`) — facturas emitidas, facturación total, nº de clientes/productos. Vanity de negocio. Explorar API.
- **grimmory** (ex-Booklore, libros, ns `media`) — libros totales, por tipo/categoría/autor, series, y por usuario: progreso de lectura, libros terminados, ratings, sesiones/tiempo de lectura. NO tiene exporter oficial ni (confirmado) endpoint nativo; existe un exporter de comunidad `arturgoms/homelab` (booklore/metrics-exporter) que va **contra la BD** con esquema de Booklore — probablemente requiere adaptar por el rename booklore→grimmory. Alternativa preferible: exporter contra la API REST de Grimmory. Verificar antes si Grimmory expone `/actuator/prometheus` (Spring Boot) → si sí, se cae de esta tarea.
- **jDownloader / Invidious** (ns `media`/`arr`) — descargas completadas, datos totales descargados. Vanity menor; opcional.

## Notas técnicas

- Patrón: exporter Python (`prometheus_client`) desplegado en `monitoring` (o junto al servicio), con Service + anotaciones `prometheus.io/*` para autoscrape de VictoriaMetrics, calcando el patrón de los demás exporters.
- Credenciales de API vía SealedSecret.
- Imagen: construir propia (repo `ghcr.io/danielramosacosta/*`, ya hay precedente con norznab/jq) o usar script montado.

## Fuera de alcance

- Los exporters nativos/comunidad (crowdsec, traefik, navidrome, minecraft/mc-monitor, deluge) → van en NASKS-67.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Exporter custom para wger desplegado (workouts, volumen, peso) y scrapeado por VictoriaMetrics
- [ ] #2 Exporter custom para FacturaScripts desplegado (facturas, facturación, clientes) y scrapeado
- [ ] #3 Métricas de grimmory (libros/lectura) expuestas a Prometheus, ya sea vía endpoint nativo o exporter custom, y scrapeadas
- [ ] #4 Todas las métricas actualizándose correctamente (no valores stale/cero) y consultables en VictoriaMetrics
- [ ] #5 Exporter custom para Navidrome (recuentos de canciones/álbumes/artistas y reproducciones) vía Subsonic API, desplegado y scrapeado por VictoriaMetrics
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Desplegar con /deploy
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Navidrome añadido al alcance (2026-08-10): su Prometheus nativo (`ND_PROMETHEUS_ENABLED`, ya activado en NASKS-67) solo expone `navidrome_info` (versión) + métricas Go — NO recuentos de librería. Para vanity de música hace falta exporter custom contra la Subsonic API (p.ej. `getScanStatus` para totales, o `getArtists`/`getAlbumList2`). Credenciales de admin de Navidrome vía SealedSecret.
<!-- SECTION:NOTES:END -->
