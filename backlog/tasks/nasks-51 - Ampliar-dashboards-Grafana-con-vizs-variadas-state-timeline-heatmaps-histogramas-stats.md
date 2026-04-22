---
id: NASKS-51
title: >-
  Ampliar dashboards Grafana con vizs variadas (state timeline, heatmaps,
  histogramas, stats)
status: To Do
assignee: []
created_date: '2026-04-21 22:20'
labels:
  - monitoring
  - grafana
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Contexto
========

El dashboard `Main` (uid `da4564c`) tiene 65 paneles muy centrados en hardware (System/SSDs/HDDs/UPS) y usa casi en exclusiva `timeseries` + `gauge`. Hay mucha info de servicios sin explotar y queremos meter vizs más variadas (state timeline, heatmaps, histogramas, stats con sparkline) para sacar partido al stack actual.

Stack relevante:
- **Media**: Jellyfin, Navidrome, Immich, Invidious, Booklore, Beets, SFTPGo
- **Arr/Downloads**: Sonarr, Radarr, Lidarr, Deluge, slskd, jdownloader
- **Auth/Edge**: Authelia, Traefik
- **Datos**: Postgres, MariaDB, Valkey
- **Plataforma**: ArgoCD, Sealed Secrets, Reloader, Gluetun, Cloudflare, SMTP relay
- **Observabilidad**: VictoriaMetrics (`P4169E866C3094E38`), Loki (`P8E80F9AEF21F6940`), node-exporter, kube-state-metrics, smartctl-exporter, nut-exporter, promtail
- **NixOS / NAS**: `quadro-ctl`, `quadro-sensors` (fans/temps custom)

Ideas por tipo de viz
======================

State timeline / Status history
-------------------------------
- **Service up/down strip**: una fila por servicio (jellyfin, immich, navidrome, *arr, postgres, authelia…) con `up{job=...}` o `kube_pod_status_phase`. Sustituye los stats sueltos de "Cluster Health".
- **UPS power state** a lo largo del tiempo (`OL → OB → CHRG → OL`) — hoy solo es stat instantáneo. Útil para ver microcortes.
- **ArgoCD sync/health state** por app (`argocd_app_info{sync_status, health_status}`).
- **Pod restarts** como eventos discretos (no timeseries).
- **Queue state** Deluge / slskd / jdownloader (idle/downloading/seeding/error).

Heatmap
-------
- **Traefik request latency heatmap** (`traefik_service_request_duration_seconds_bucket`) — el clásico.
- **Logins Authelia** por hora del día × día de semana — patrón de uso personal.
- **Volumen logs Loki** por namespace (`sum by (namespace) (rate({...}[$__interval]))`).
- **CPU/RAM por pod en grid** (filas = pods, color = utilización) — saturación de servicios bursty.
- **Disk IOPS por device** (más legible que múltiples lines superpuestas).

Histograma
----------
- **Distribución duración requests Traefik** (histogram puro, no cumulative).
- **Tamaño uploads Immich** parseando logs nginx en Loki.
- **Duración transcodes Jellyfin** vía Loki.
- **Bitrate tracks Navidrome** (query SQLite ya documentada en memoria).
- **Tamaño descargas slskd/deluge** completadas.

Stat (vanity metrics + sparklines)
----------------------------------
- **Library counters**: nº pelis/series (Sonarr/Radarr API), álbumes (Lidarr/Navidrome), fotos (Immich), libros (Booklore).
- **TB en `/cold-data`** con sparkline de crecimiento.
- **Días desde último corte de luz** (de UPS state).
- **kWh consumidos hoy** (derivable de `ups_load * nominal_power` integrado).
- **Usuarios activos hoy** (distinct Authelia logins).
- **Top 3 servicios más solicitados 24h** (Traefik).
- **Tiempo desde último backup exitoso**.
- **Certs TLS por expirar** (Traefik metric).

Otros
-----
- **Geomap** de requests externas con geoip de logs Traefik en Loki.
- **Pie/bar gauge** de ocupación `/cold-data` por tipo (movies/series/music/photos/backups) vía node-exporter textfile collector + `du`.
- **Bar chart** de "albums añadidos a Lidarr por semana" (encaja con flow music-library).

Organización propuesta
======================

Considerar partir el dashboard `Main` en varios:
- *Storage Health* (lo actual de SSD/HDD/UPS/system)
- *Media* (Jellyfin/Immich/Navidrome/Invidious/Booklore)
- *Downloads* (arr + deluge + slskd + jdownloader)
- *Auth & Edge* (Authelia + Traefik + geomap)
- *Cluster* (ArgoCD + restarts + state timelines)

Así caben heatmaps grandes sin competir con los gauges del NAS.

Quick wins sugeridos
====================
1. **State timeline de servicios** (sustituye 6 stats de Cluster Health).
2. **Heatmap latencia Traefik**.
3. **Library counters** vía Sonarr/Radarr/Lidarr/Immich APIs.
<!-- SECTION:DESCRIPTION:END -->
