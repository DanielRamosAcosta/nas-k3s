---
id: NASKS-85
title: Añadir scraparr (exporter de la suite *arr) al stack de monitoring
status: Done
assignee: []
created_date: '2026-08-09 19:13'
updated_date: '2026-08-09 19:31'
labels: []
dependencies: []
references:
  - 'https://github.com/thecfu/scraparr'
  - 'https://codeberg.org/thecfu/scraparr'
  - 'https://grafana.com/grafana/dashboards/22934'
priority: low
type: feature
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Levantar `scraparr` (exporter de Prometheus para la suite *arr) como nuevo servicio en el namespace `monitoring`, scrapeando Sonarr/Radarr/Lidarr, para que VictoriaMetrics recoja métricas de salud y actividad de esas apps.

## 🎯 Contexto funcional

Sonarr/Radarr/Lidarr no exponen métricas Prometheus nativas. `scraparr` consulta sus APIs y publica métricas (estado de colas, salud, nº de items, tamaño de biblioteca, indexers, etc.) en `/metrics`, permitiendo paneles y alertas sobre el estado del stack *arr. El dashboard de Grafana queda fuera de alcance (decisión del usuario: solo el exporter; el oficial 22934 se puede importar después).

## ⚙️ Contexto técnico

- **Imagen:** `ghcr.io/thecfu/scraparr`, versión estable `3.1.0`. Puerto `7100`, métricas en `/metrics`. Licencia GPL-3.0. (Desarrollo principal en Codeberg; GitHub es mirror.)
- **Targets:** apps *arr en el namespace `arr` (cross-namespace DNS):
  - `http://sonarr.arr.svc.cluster.local:8989`
  - `http://radarr.arr.svc.cluster.local:7878`
  - `http://lidarr.arr.svc.cluster.local:8686`
- **Config:** scraparr admite env vars o `config.yaml`. Se usará el patrón de env (calcando immich-exporter): URLs públicas vía ConfigMap (`SONARR_URL`/`RADARR_URL`/`LIDARR_URL`) + API keys vía SealedSecret strict (`SONARR_API_KEY`/`RADARR_API_KEY`/`LIDARR_API_KEY`), ambas inyectadas como env. Las API keys las genera cada *arr (Settings → General) y se sellan con `encrypt-secret.sh system-agnostic` (ns `monitoring`).
- **Manifiestos (patrón exporter, calcar immich-exporter/nut):**
  - `lib/versions.json`: entrada `scraparr` (imagen + versión).
  - `lib/monitoring/scraparr/scraparr.libsonnet`: `Deployment` (1 réplica, puerto 7100, probe HTTP `/metrics`) + `Service` con `u.metrics('7100')` + ConfigMap (URLs) + SealedSecret (API keys).
  - `lib/monitoring/scraparr/scraparr.secrets.json`: API keys selladas.
  - `environments/monitoring/main.jsonnet`: cablear `scraparr.new()`.
- **Scrape:** `u.metrics('7100')` estampa `prometheus.io/{scrape,port,path}` en el Service; el job `kubernetes-service-endpoints` de VictoriaMetrics lo autodescubre. NO hay que tocar `victoriametrics.yml`.
- **ArgoCD:** `u.Environment`/`u.labelApp` estampan la etiqueta `app`; ArgoCD genera la Application automáticamente.

## Fuera de alcance

- Dashboard de Grafana (oficial 22934) — se importará en otra tarea/paso si se quiere.
- Otras apps *arr no desplegadas (prowlarr, bazarr, readarr…).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Existe lib/monitoring/scraparr/scraparr.libsonnet con Deployment (puerto 7100), Service con u.metrics('7100') y SealedSecret con las API keys de sonarr/radarr/lidarr
- [x] #2 La imagen ghcr.io/thecfu/scraparr está pineada en lib/versions.json (3.1.0)
- [x] #3 Las URLs internas de sonarr/radarr/lidarr (ns arr) se inyectan vía ConfigMap (env) y las API keys vía SealedSecret (env)
- [x] #4 El exporter queda cableado en environments/monitoring/main.jsonnet y ArgoCD genera su Application automáticamente
- [x] #5 VictoriaMetrics descubre y scrapea el target vía las anotaciones prometheus.io/* (sin tocar victoriametrics.yml) y las métricas scraparr_* son consultables
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Desplegar con /deploy
<!-- DOD:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
scraparr desplegado en monitoring y dashboard "scraparr" creado en Grafana.

Exporter ghcr.io/thecfu/scraparr:3.1.0 en ns monitoring: Deployment (puerto 7100) + Service (autoscrape vía prometheus.io/*, job kubernetes-service-endpoints) + ConfigMap (URLs internas de sonarr/radarr/lidarr en ns arr) + SealedSecret (SONARR/RADARR/LIDARR_API_KEY). Desplegado vía PR #181. Las 3 API keys se extrajeron de los config.xml de cada app a fichero (sin exponerlas), se verificaron contra /system/status (HTTP 200) y se sellaron. Pod Running 1/1; los 3 conectores reportan "metrics updated" sin errores de auth. VictoriaMetrics scrapea (sonarr_series_total=29, radarr_movies_total=280, lidarr_artists_total=166).

Dashboard Grafana "scraparr" (/d/scraparr/scraparr, uid scraparr) con 14 paneles: overview (services up, series/movies/artists, queue, missing), calidad por app (bargauge min=0 + sort_desc), almacenamiento (tamaño por app + disco libre), y donuts de estado/monitored. Creado vía API — no versionado en git.
<!-- SECTION:FINAL_SUMMARY:END -->
