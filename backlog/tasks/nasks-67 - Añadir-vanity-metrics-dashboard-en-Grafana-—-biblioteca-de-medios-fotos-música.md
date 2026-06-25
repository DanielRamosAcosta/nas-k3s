---
id: NASKS-67
title: >-
  Añadir vanity metrics dashboard en Grafana — biblioteca de medios, fotos,
  música
status: To Do
assignee: []
created_date: '2026-06-19 17:58'
updated_date: '2026-06-21 09:55'
labels:
  - grafana
  - monitoring
  - media
dependencies: []
references:
  - 'https://github.com/thecfu/scraparr'
  - 'https://github.com/rafaelvieiras/jellyfin-exporter'
  - 'https://github.com/eithan1231/immich-exporter'
  - 'https://grafana.com/grafana/dashboards/24489-navidrome/'
  - 'https://grafana.com/grafana/dashboards/12896-radarr-v3/'
  - 'https://github.com/Boerderij/Varken'
priority: low
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Objetivo

Crear un dashboard de Grafana con "vanity metrics" del NAS: números grandes que muestran el tamaño de las bibliotecas, actividad de usuarios y estado del stack de medios. Inspirado en la práctica habitual de la comunidad homelab (r/selfhosted, r/homelab).

---

## Contexto e investigación

La comunidad homelab usa principalmente **Prometheus exporters → Grafana stat/piechart panels**. El patrón es siempre el mismo: números grandes en pantalla, cuantos más dígitos mejor. Las métricas de ego más comunes son recuentos de biblioteca (películas, series, episodios, canciones, fotos) y actividad de usuarios (streams activos, quién está viendo qué).

Se investigaron fuentes primarias (código fuente de exporters, dashboards de Grafana Labs, Reddit). Resultados verificados adversarialmente (19/25 claims confirmados, 6 refutados).

---

## Exporters disponibles (opciones)

### Opción A — Scraparr (all-in-one, recomendado para arr-stack + Jellyfin)

- Repo: https://github.com/thecfu/scraparr
- Actualizado activamente (último commit 2026-06-17)
- Cubre en un solo pod: Radarr, Sonarr, Lidarr, Jellyfin
- Métricas que expone:
  - `radarr_movies_total`, `radarr_disk_size_total`
  - `sonarr_series_total`, `sonarr_episodes_total`, `sonarr_series_download_percentage` (% completitud por serie, con label `series`)
  - `lidarr_artists_total`, `lidarr_tracks_total`, `lidarr_releases_total`
  - `jellyfin_number_of_users`, `jellyfin_number_of_devices`, `jellyfin_number_of_movies`, `jellyfin_number_of_series`, `jellyfin_sessions`

### Opción B — jellyfin-exporter (más detallado para Jellyfin)

- Repo: https://github.com/rafaelvieiras/jellyfin-exporter
- Expone `jellyfin_media_count{type}` con 12 tipos (movies, shows, episodes, artists, songs, albums, music_videos, box_sets, books, trailers, programs, items)
- Expone `jellyfin_stream_count` con 10 labels (play_method, audio_codec, video_codec, transcode_reasons, usuario)
- Expone `jellyfin_connected_clients_count` por usuario y dispositivo
- Más granular que Scraparr para Jellyfin, pero solo cubre Jellyfin

### Opción C — immich-exporter (para Immich)

- Repo: https://github.com/eithan1231/immich-exporter
- El dashboard oficial de Immich (ID 22555) es **solo operacional** — no tiene vanity metrics
- Este exporter de terceros expone (por usuario con labels `user_id`, `user_name`):
  - `immich_statistics_user_photo_count`
  - `immich_statistics_user_video_count`
  - `immich_statistics_user_usage` (bytes)
  - `immich_statistics_user_quota_bytes`
- Dashboard oficial del exporter: pie charts "User Photos" y "User Videos"

### Opción D — Navidrome (métricas nativas)

- Dashboard ID 24489 en Grafana Labs: https://grafana.com/grafana/dashboards/24489-navidrome/
- Sección "Media Statistics": track count, album count, artist count, scan statistics
- Verificar si Navidrome expone endpoint Prometheus nativo o requiere exporter

### Opción E — Exporters custom (si hiciera falta)

Para servicios sin exporter verificado en la comunidad, se pueden construir exporters custom sencillos (Python + prometheus_client) que llamen a las APIs REST de cada servicio:

- **Booklore** — libros en biblioteca, libros leídos (explorar API)
- **wger** — workouts registrados, ejercicios completados (tiene API REST documentada)
- **FacturaScripts** — facturas emitidas, clientes (explorar API)
- **Traefik** — ya expone métricas Prometheus nativas; requests totales por servicio/ruta
- **CrowdSec** — amenazas bloqueadas, IPs baneadas (tiene exporter Prometheus oficial)

---

## Métricas de vanity candidatas (priorizado)

### Tier 1 — Fácil (exporter probado, cobertura alta)
| Servicio | Métrica | Visualización sugerida |
|----------|---------|----------------------|
| Radarr | Películas en biblioteca | Stat panel grande |
| Sonarr | Series / episodios totales | Stat panel |
| Lidarr | Artistas / álbumes / tracks | Stat panel |
| Jellyfin | Usuarios activos, streams activos | Stat + gauge |
| Jellyfin | Direct play vs transcode | Piechart |
| Immich | Fotos y vídeos por usuario | Piechart por usuario |
| Immich | GB totales almacenados | Stat panel |

### Tier 2 — Medio (requiere verificación o config extra)
| Servicio | Métrica | Visualización sugerida |
|----------|---------|----------------------|
| Navidrome | Canciones / álbumes / artistas | Stat panel |
| Sonarr | % completitud por serie | Table o bar chart |
| Traefik | Requests totales por servicio | Time series o stat |
| CrowdSec | IPs baneadas totales | Stat panel (ego máximo) |

### Tier 3 — Custom (si se construye exporter propio)
| Servicio | Métrica | Nota |
|----------|---------|------|
| Booklore | Libros en biblioteca | Explorar API primero |
| wger | Workouts completados | API REST documentada |
| FacturaScripts | Facturas emitidas | Explorar API |

---

## Decisiones de implementación pendientes

1. **¿Scraparr vs jellyfin-exporter individual?** — Scraparr es más cómodo (un solo pod), jellyfin-exporter da más granularidad para Jellyfin. Se pueden usar ambos si no hay conflicto de nombres de métricas.
2. **¿Dashboard único consolidado o por servicio?** — La comunidad no tiene un dashboard canónico "todo en uno"; hay que construirlo. Un único dashboard de vanity tiene más impacto visual.
3. **¿Navidrome expone Prometheus nativo?** — Verificar antes de asumir que necesita exporter.
4. **Namespace de despliegue** — Scraparr e immich-exporter probablemente van en `monitoring` junto al resto de exporters.

---

## Referencias

- Scraparr: https://github.com/thecfu/scraparr
- jellyfin-exporter: https://github.com/rafaelvieiras/jellyfin-exporter
- immich-exporter: https://github.com/eithan1231/immich-exporter
- Dashboard Navidrome (ID 24489): https://grafana.com/grafana/dashboards/24489-navidrome/
- Dashboard Radarr v3 (ID 12896): https://grafana.com/grafana/dashboards/12896-radarr-v3/
- Varken (referencia histórica, abandonado desde 2020): https://github.com/Boerderij/Varken
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard de Grafana con vanity metrics visibles y funcionales para al menos Radarr, Sonarr, Lidarr, Jellyfin e Immich
- [ ] #2 Exporters desplegados como recursos Kubernetes en el namespace correspondiente y scrapeados por VictoriaMetrics
- [ ] #3 Métricas actualizándose correctamente (no valores a cero o stale)
- [ ] #4 Dashboard guardado en Grafana (provisionado o manual)
<!-- AC:END -->
