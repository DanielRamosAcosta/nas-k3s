---
title: "Anotaciones de scrape para servicios con metricas sin recoger"
status: In Progress
priority: 3
labels: [monitoring, observability]
parent:
references: ["[[Dar de alta exporters de metricas faltantes]]"]
created_date: 2026-10-16 19:15
---

## Description

## 📌 TLDR

Auditar los servicios que ya exponen `/metrics` nativo pero no se están scrapeando por faltarles las anotaciones `prometheus.io/*`, y añadírselas. Caso confirmado: **Loki y Promtail** (self-metrics del pipeline de logs), que hoy no llegan a VictoriaMetrics.

## 🎯 Contexto funcional

Varios componentes exponen métricas que no estamos recogiendo. El pipeline de logs (Loki + Promtail) es el más relevante: no tenemos visibilidad de su salud (ingesta, errores, latencia, cardinalidad), justo la infraestructura de la que dependemos para depurar todo lo demás.

Verificado en VictoriaMetrics que **sí** se scrapean ya (no tocar): Traefik, Authelia, Synapse, Wger (django_*), Navidrome, Immich, Jellyfin, Deluge, SftpGo, CrowdSec, kube-state-metrics, node/smartctl, VictoriaMetrics self.

## ⚙️ Contexto técnico

- **Loki** (`lib/monitoring/loki/loki.libsonnet`, StatefulSet): expone `/metrics` en el puerto 3100 nativamente. Falta la anotación de scrape en el pod/service.
- **Promtail** (`lib/monitoring/promtail/promtail.libsonnet`, DaemonSet): expone `/metrics` (puerto 9080). Falta anotación.
- Patrón a aplicar: las mismas anotaciones `prometheus.io/scrape: 'true'` + `prometheus.io/port` que usan los demás exporters, para que el job `kubernetes-pods` de VictoriaMetrics los recoja.
- Antes de cerrar, hacer una pasada de auditoría: comprobar si algún otro workload expone `/metrics` sin anotación (p. ej. mautrix-whatsapp, CouchDB nativo, componentes de ArgoCD) y decidir si vale la pena recogerlo.

## Acceptance Criteria

- [ ] #1 Loki scrapeado por VictoriaMetrics (`loki_build_info` presente)
- [ ] #2 Promtail scrapeado por VictoriaMetrics (`promtail_*` presente)
- [ ] #3 Auditoría del resto de workloads confirmada: documentado qué expone `/metrics` sin recoger y si se añade o se descarta

## Implementation Plan

1. Añadir anotaciones de scrape a Loki (Service, puerto 3100) y Promtail (pod del DaemonSet, puerto 9080), siguiendo el patrón del repo (`u.metrics(...)` sobre Service → job `kubernetes-service-endpoints`; anotación en pod → job `kubernetes-pods`).
2. Auditar el resto de workloads contra VictoriaMetrics (`P4169E866C3094E38`) para distinguir los que exponen `/metrics` nativo sin recoger de los que necesitan un exporter aparte.
3. Añadir los candidatos nativos adicionales que aparezcan en la auditoría.

## Implementation Notes

### Cambios aplicados

- **Loki** (`lib/monitoring/loki/loki.libsonnet`): `u.metrics(port='3100')` sobre el Service.
- **Promtail** (`lib/monitoring/promtail/promtail.libsonnet`): anotaciones `prometheus.io/scrape` + `prometheus.io/port: '9080'` en el pod del DaemonSet (como el agent de CrowdSec; no se crea un Service solo para scrapear un workload per-node).
- **Grafana** (`lib/monitoring/grafana/grafana.libsonnet`): `u.metrics(port='3000')` sobre el Service — expone `/metrics` nativo y no se estaba recogiendo.
- **VictoriaMetrics** (`lib/monitoring/victoriametrics/victoriametrics.libsonnet`): `u.metrics(port='8428')` sobre el Service — self-scrape de la propia TSDB, que tampoco se recogía (no existe job self en `victoriametrics.yml`, al contrario de lo que suponía el TLDR).

### Auditoría (AC #3)

Verificado directamente contra VictoriaMetrics qué métricas llegan hoy, en lugar de fiarse de suposiciones:

**Candidatos nativos añadidos** (exponían `/metrics` sin anotación): Loki, Promtail, Grafana, VictoriaMetrics self.

**Descartados — ya cubiertos** (falsos positivos de la auditoría inicial):
- Sonarr/Radarr/Lidarr: no exponen `/metrics` Prometheus nativo; se recogen vía **scraparr** (ya scrapeado).
- Jellyfin: cubierto vía exporter (métricas `jellyfin_*` presentes en VM).
- NUT-exporter: ya scrapeado vía el job estático `nut-salicru` de `victoriametrics.yml`.

**Necesitan un exporter aparte** (no tienen `/metrics` nativo) → fuera de scope, pertenecen a [[Dar de alta exporters de metricas faltantes]]: Postgres, Valkey/Redis, MariaDB, CouchDB, mautrix-whatsapp, y el resto de apps de negocio/media/juegos.
