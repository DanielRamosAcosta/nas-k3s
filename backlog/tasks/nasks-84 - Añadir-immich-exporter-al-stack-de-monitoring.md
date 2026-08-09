---
id: NASKS-84
title: Añadir immich-exporter al stack de monitoring
status: In Progress
assignee: []
created_date: '2026-08-09 18:24'
updated_date: '2026-08-09 18:34'
labels: []
dependencies: []
references:
  - 'https://github.com/eithan1231/immich-exporter'
  - 'https://hub.docker.com/r/eithan1231/immich-exporter'
modified_files:
  - lib/versions.json
  - lib/monitoring/immich-exporter/immich-exporter.libsonnet
  - lib/monitoring/immich-exporter/immich-exporter.secrets.json
  - environments/monitoring/main.jsonnet
priority: low
type: feature
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Levantar el exporter de Prometheus `eithan1231/immich-exporter` como nuevo servicio en el namespace `monitoring` para exponer métricas de alto nivel de Immich (usuarios, nº de fotos/vídeos, jobs, almacenamiento) y que VictoriaMetrics las scrapee automáticamente.

## 🎯 Contexto funcional

Immich ya expone métricas técnicas propias en `:8081`, pero no métricas de negocio/uso (cuántos assets hay, por usuario, estado de jobs, almacenamiento). `immich-exporter` consulta la API de Immich y publica esas métricas en formato Prometheus. Esto permite construir paneles y alertas sobre el uso real de la biblioteca. El dashboard de Grafana del repo queda fuera de alcance (decisión del usuario: solo el exporter).

## ⚙️ Contexto técnico

- **Imagen:** `eithan1231/immich-exporter` (Docker Hub, multiarch amd64/arm64), tag pineado `2025-05-12-commit-241dce4` (digest índice `sha256:4f4857b21fbaa8512f39c20491750d9a9b645abf9ea1cc23266b8efe7c1850dd`). Repo poco activo (último push 2025-05-12), tener en cuenta.
- **Puerto/path:** escucha en `3000`, métricas en `/metrics` (confirmado en `src/index.ts`).
- **Config (env):** `IMMICH_HOST=http://immich.media.svc.cluster.local:2283` (svc interno de Immich, ns `media`) y `IMMICH_KEY` = API key de Immich (secreto → SealedSecret strict, ns `monitoring`).
- **Manifiestos (patrón exporter, calcar nut/smartctl):**
  - `lib/versions.json`: entrada `immichExporter` (imagen + tag).
  - `lib/monitoring/immich-exporter/immich-exporter.libsonnet`: `Deployment` (1 réplica) + `Service` con `u.metrics('3000')` + `SealedSecret` (`u.sealedSecret.forEnv`) con `u.envVars.fromSealedSecret`.
  - `lib/monitoring/immich-exporter/immich-exporter.secrets.json`: API key sellada.
  - `environments/monitoring/main.jsonnet`: cablear `immichExporter.new()`.
- **Scrape:** `u.metrics('3000')` estampa las anotaciones `prometheus.io/{scrape,port,path}` en el Service; el job `kubernetes-service-endpoints` de VictoriaMetrics lo autodescubre. NO hay que tocar `victoriametrics.yml`.
- **ArgoCD:** `u.Environment`/`u.labelApp` estampan la etiqueta `app`; ArgoCD genera la Application automáticamente y Reloader reinicia el pod ante cambios de config/secret.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Existe lib/monitoring/immich-exporter/immich-exporter.libsonnet con Deployment (1 réplica), Service con u.metrics('3000') y SealedSecret para IMMICH_KEY
- [x] #2 La imagen eithan1231/immich-exporter está pineada en lib/versions.json con el tag 2025-05-12-commit-241dce4
- [x] #3 IMMICH_HOST apunta a http://immich.media.svc.cluster.local:2283 y IMMICH_KEY se inyecta desde el SealedSecret
- [x] #4 El exporter queda cableado en environments/monitoring/main.jsonnet y ArgoCD genera su Application automáticamente
- [ ] #5 VictoriaMetrics descubre y scrapea el target vía las anotaciones prometheus.io/* (sin tocar victoriametrics.yml) y sus métricas son consultables
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Desplegar con /deploy
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implementado siguiendo el patrón de exporter (calcado de nut/smartctl + configEnv como immich):

- `lib/versions.json`: entrada `immichExporter` → `eithan1231/immich-exporter:2025-05-12-commit-241dce4`.
- `lib/monitoring/immich-exporter/immich-exporter.libsonnet`: Deployment (1 réplica, puerto 3000, probe HTTP `/metrics`), Service con `u.metrics('3000')`, ConfigMap `configEnv` con `IMMICH_HOST=http://immich.media.svc.cluster.local:2283`, y SealedSecret (`forEnv`) con `IMMICH_KEY`.
- `lib/monitoring/immich-exporter/immich-exporter.secrets.json`: API key sellada (strict, ns monitoring, name `immich-exporter-sealed-secret`). Key generada desde cuenta admin con permisos `server.statistics` + `server.storage` (verificado en docs oficiales de Immich por endpoint).
- `environments/monitoring/main.jsonnet`: cableado `immichExporter.new()`.

`tk eval environments/monitoring` compila limpio y genera los 4 recursos con label `app=immich-exporter`, anotaciones `prometheus.io/*` en el Service y las dos env vars correctas. Nota: la anotación de Reloader sale null, pero es consistente con TODOS los workloads de monitoring (no es específico de este cambio).

Pendiente: /deploy y verificar scrape en VictoriaMetrics (AC #5).
<!-- SECTION:NOTES:END -->
