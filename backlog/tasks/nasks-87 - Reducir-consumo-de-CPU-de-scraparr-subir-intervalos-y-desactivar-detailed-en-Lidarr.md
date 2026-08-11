---
id: NASKS-87
title: >-
  Reducir consumo de CPU de scraparr: subir intervalos y desactivar detailed en
  Lidarr
status: In Progress
assignee: []
created_date: '2026-08-11 18:32'
labels: []
dependencies: []
references:
  - 'https://github.com/thecfu/scraparr'
  - 'https://github.com/thecfu/scraparr/blob/master/docs/configuration.md'
  - 'https://github.com/thecfu/scraparr/blob/master/docs/connectors.md'
priority: medium
type: chore
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

El exporter `scraparr` consume ~0.3 cores de forma continua desde su despliegue el 2026-08-09 ~20:00, subiendo el baseline de CPU del nodo de ~1.0 a ~1.4 cores y provocando que los ventiladores oscilen ("sierra") de forma permanente. Se mitiga subiendo el intervalo de scrape de los 4 connectors a 300s y desactivando el modo `detailed` de Lidarr.

## 🎯 Contexto funcional

Investigando un comportamiento raro en las métricas del NAS (ventiladores serrando desde el 2026-08-09 20:00, temperatura de CPU oscilante), se correlacionó la transición con la tanda de despliegues de exporters de esa tarde. La CPU base del nodo dio un escalón permanente de ~1.0 → ~1.4 cores justo a esa hora. El único consumidor nuevo relevante es `scraparr` (~0.3 cores continuos); el resto de exporters añadidos son residuales (~0.002 cores).

La causa raíz está en el connector de Lidarr: con el modo `detailed` itera toda la librería musical haciendo 2 llamadas API extra por artista (álbumes + track files) en cada ciclo, emitiendo cientos de warnings "No statistics found for <álbum>". Con el intervalo por defecto de 30s, ese bucle corre constantemente. Para un dashboard vanity de homelab no se necesita ni esa frecuencia ni el detalle por-artista.

## ⚙️ Contexto técnico

Cambios solo en `lib/monitoring/scraparr/scraparr.libsonnet` (bloque `configEnv`), aplicados vía GitOps (ArgoCD sync + Reloader reinicia el pod). scraparr (thecfu) se configura por env vars con patrón `SERVICE_FIELD`:

- Añadir `SONARR_INTERVAL=300`, `RADARR_INTERVAL=300`, `LIDARR_INTERVAL=300`, `JELLYFIN_INTERVAL=300` (default es 30).
- Añadir `LIDARR_DETAILED=false` para cortar la iteración por artista (álbumes + track files) y el flood de warnings; se mantienen las métricas de librería (artistas, disco, calidad), se pierden solo las por-artista (`lidarr_artist_tracks`, `lidarr_artist_disk_size`).

Verificación en Prometheus (VictoriaMetrics, uid P4169E866C3094E38): `sum(rate(container_cpu_usage_seconds_total{namespace="monitoring", pod=~"scraparr.*"}[5m]))`, baseline del nodo `sum(rate(node_cpu_seconds_total{mode!="idle"}[5m]))`, y ventilador `max by (sensor)(node_hwmon_fan_rpm{sensor="fan3", chip=~"3_4_2:1_1_0003:0c70:f00d_.*"})`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Los 4 connectors (sonarr, radarr, lidarr, jellyfin) tienen interval=300 configurado vía env en scraparr.libsonnet
- [ ] #2 El modo detailed de Lidarr queda desactivado (LIDARR_DETAILED=false)
- [ ] #3 El consumo continuo de CPU de scraparr baja de ~0.3 cores a residual
- [ ] #4 El baseline de CPU del nodo vuelve a ~1.0 core y fan3 recupera el patrón plano previo al 2026-08-09 20:00
<!-- AC:END -->
