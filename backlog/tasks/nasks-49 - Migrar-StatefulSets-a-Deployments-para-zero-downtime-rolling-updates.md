---
id: NASKS-49
title: Migrar StatefulSets a Deployments para zero-downtime rolling updates
status: Done
assignee: []
created_date: '2026-04-12 00:04'
updated_date: '2026-04-12 01:06'
labels:
  - infra
  - zero-downtime
dependencies: []
priority: medium
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Actualmente 15 apps usan StatefulSet con 1 réplica, lo que causa ~10s de downtime en cada deploy porque K8s mata el pod viejo antes de crear el nuevo. Ninguna de estas apps necesita identidad estable de pod ni arranque ordenado — solo usan hostPath para datos.

Al migrarlas a Deployment con strategy RollingUpdate, K8s creará el pod nuevo primero, esperará a que pase readiness, redirigirá tráfico, y luego matará el viejo.

**Apps a migrar (15):**
- ARR: Radarr, Sonarr, Lidarr, Deluge, Slskd, JDownloader
- Media: Jellyfin, Navidrome, SFTPgo, Immich, Booklore, Beets
- Cache: Valkey
- Business: FacturaScripts

**No migrar (4):** PostgreSQL, MariaDB, VictoriaMetrics, Loki (bases de datos/TSDB reales)

**Ya son Deployments (2):** Invidious, Norznab
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Migradas 15 apps de StatefulSet a Deployment para zero-downtime rolling updates. También se corrigió norznab que ya usaba deployment.new() pero tenía el campo nombrado `statefulSet`.

**Apps migradas:** radarr, sonarr, lidarr, deluge, slskd, jdownloader, norznab, jellyfin, navidrome, sftpgo, immich, booklore, beets, valkey, facturascripts.

**Sin cambios (databases/TSDB):** postgres, mariadb, victoriametrics, loki.

CI pasó, manifiestos publicados. ArgoCD sincroniza automáticamente con prune=true.
<!-- SECTION:FINAL_SUMMARY:END -->
