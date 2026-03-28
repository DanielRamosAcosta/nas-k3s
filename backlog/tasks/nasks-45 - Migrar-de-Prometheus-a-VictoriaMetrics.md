---
id: NASKS-45
title: Migrar de Prometheus a VictoriaMetrics
status: Done
assignee: []
created_date: '2026-03-27 19:27'
updated_date: '2026-03-28 14:16'
labels:
  - monitoring
  - migration
dependencies: []
references:
  - lib/monitoring/prometheus/prometheus.libsonnet
  - lib/monitoring/grafana/grafana.libsonnet
  - environments/monitoring/main.jsonnet
  - environments/versions.json
priority: medium
ordinal: 0.030517578125
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reemplazar Prometheus por VictoriaMetrics como sistema de métricas del cluster para aprovechar:

- **Menor consumo de recursos** (RAM, CPU, disco) — importante en el NAS
- **Mejor compresión** (~0.4 bytes/sample vs ~1.3) — ~4 GB/año vs ~12 GB/año a raw 30s
- **MetricsQL** — superset retrocompatible de PromQL
- **Queries más rápidas** sobre rangos largos de tiempo
- **Retención prácticamente ilimitada** — ~40 GB en 10 años es asumible en un NAS

> **Nota:** El downsampling nativo es feature Enterprise. Se ha solicitado licencia gratuita para homelab (ver DRAFT-2). Esta migración se hace sin downsampling, con `-retentionPeriod=100y`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Scrape interval reducido a 30s y validado en Prometheus antes de migrar (24-48h sin problemas en dashboards)
- [x] #2 VictoriaMetrics (single-binary) desplegado y scrapeando los 7 jobs actuales
- [x] #3 Retención configurada con `-retentionPeriod=100y`
- [x] #4 Datos históricos de Prometheus importados con `vmctl` y verificados (comparar count de series y rango temporal)
- [x] #5 Grafana apuntando a VictoriaMetrics (manteniendo el nombre de datasource "Prometheus" para no romper dashboards)
- [x] #6 Todos los dashboards existentes funcionan sin modificaciones
- [x] #7 Labels de ArgoCD de los exporters re-asignados (no dependen de la app `prometheus`)
- [ ] #8 Prometheus retirado del cluster (tras periodo de gracia post-cutover)
- [ ] #9 ArgoCD sincroniza correctamente el nuevo stack
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Fase 0 — Preparación

1. Reducir scrape interval de 5s a 30s en Prometheus
2. Dejar correr 24-48h y validar que los dashboards de Grafana siguen funcionando con la nueva granularidad (revisar que queries con `rate()` sobre ventanas cortas `[<2m]` no se rompan)
3. Re-etiquetar los exporters con label `app: monitoring-exporters` (ver decisión #11). Recursos afectados (verificado con `kubectl`):
   - DaemonSet/node-exporter + Service/node-exporter
   - DaemonSet/smartctl-exporter + Service/smartctl-exporter
   - DaemonSet/nut-exporter + Service/nut-exporter
   - Deployment/kube-state-metrics + Service/kube-state-metrics
4. Sincronizar ArgoCD y verificar que los exporters siguen corriendo tras el cambio de label antes de continuar

## Fase 1 — Despliegue en paralelo

5. Crear `lib/monitoring/victoriametrics/victoriametrics.libsonnet` con single-binary (imagen `victoriametrics/victoria-metrics`, puerto 8428)
6. Copiar el mismo RBAC y service account de Prometheus
7. Adaptar los scrape configs al formato de VictoriaMetrics (7 jobs — flag `-promscrape.config`; acepta formato Prometheus nativamente)
8. Storage en `/data/victoriametrics/data` (hostPath). Sin securityContext restrictivo — VM corre como root por defecto (ver decisión #12)
9. Configurar retención: `-retentionPeriod=100y` (sin downsampling, ~4 GB/año es asumible)
10. Configurar probes: startup/readiness en `/health` y `/ready` (puerto 8428)
11. Sin resource limits de CPU/RAM — se ajustarán en tarea separada una vez estabilizado (VM con ~10k series debería usar ~256-512 MB RAM)
12. Exponer como service `victoriametrics.monitoring.svc.cluster.local:8428`
13. Añadir al environment de monitoring sin quitar Prometheus
14. **Checkpoint:** verificar en `/targets` de VM (puerto 8428) que los 7 jobs están en estado UP y sin errores de scrape. No continuar hasta confirmar
15. Crear dashboard básico en Grafana con métricas internas de VM: `process_resident_memory_bytes`, `vm_rows_inserted_total`, `vm_promscrape_scrape_errors_total`. Servirá para monitorizar VM durante el paralelo y post-cutover. (No hace falta monitorizar disco — ya hay alerta de SSD configurada)

## Fase 2 — Migración de datos históricos

16. Importar métricas directamente vía API remota: `vmctl prometheus --prom-url=http://prometheus.monitoring.svc.cluster.local:9090` (no requiere snapshot ni habilitar admin API)
17. Verificar datos importados: comparar `count({__name__=~".+"})` entre Prometheus y VM, verificar rango temporal, y consultar 2-3 series concretas con timestamps específicos para confirmar que no hay corrupción ni desplazamiento temporal

## Fase 3 — Validación

18. Añadir segundo datasource en Grafana apuntando a VictoriaMetrics (temporal). **Nota:** la URL puede requerir el path `/prometheus/` (ej. `http://victoriametrics:8428/prometheus/`); si no, la raíz también expone `/api/v1/query`
19. Comparar queries clave entre ambos datasources (datos actuales + históricos). Seleccionar 3-5 panels de los dashboards más usados. Criterio de aceptación: gauges deben coincidir exactos; rates/counters tolerancia ≤5% (por diferencias en manejo de staleness entre VM y Prometheus)
20. Dejar correr ambos en paralelo unos días para acumular datos y detectar discrepancias

## Fase 4 — Cutover

18. Cambiar la URL del datasource "Prometheus" de Grafana a apuntar a VictoriaMetrics (mantener el nombre "Prometheus" para no romper dashboards)
19. Validar dashboards y queries durante unos días con Prometheus aún corriendo como fallback

## Fase 5 — Retirada de Prometheus (tras periodo de gracia de ~1 semana)

20. Retirar Prometheus del environment
21. Verificar que ArgoCD sincroniza correctamente

## Fase 6 — Cleanup

22. Borrar `lib/monitoring/prometheus/`
23. Actualizar `environments/monitoring/main.jsonnet`
24. Quitar imagen de Prometheus de `versions.json`
25. Limpiar directorio `/data/prometheus/data` del NAS

### Rollback

En cualquier momento antes de la Fase 6, se puede revertir cambiando la URL del datasource de Grafana de vuelta a `prometheus.monitoring.svc.cluster.local:9090`. Prometheus sigue corriendo hasta la Fase 5.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Investigación del stack actual

### Prometheus (v3.10.0)
- **Tipo:** StatefulSet, 1 réplica
- **Storage:** hostPath `/data/prometheus/data`
- **Scrape interval:** 5 segundos (muy agresivo)
- **Scrape configs (7 jobs):**
  1. `node-exporter` — descubrimiento de endpoints Kubernetes
  2. `kubernetes-apiservers` — HTTPS con service account token
  3. `kubernetes-nodes` — métricas de kubelet vía kube-proxy
  4. `kubernetes-pods` — filtrado por annotation `prometheus.io/scrape: true`
  5. `kubernetes-cadvisor` — métricas de contenedores
  6. `kubernetes-service-endpoints` — descubrimiento de endpoints con annotation `prometheus.io/scrape: true`
  7. `nut-salicru` — target estático para UPS (nut-exporter.monitoring.svc.cluster.local:9199)
- **RBAC:** Service account `prometheus` con ClusterRole (get/watch/list en nodes, pods, services, endpoints + /metrics)
- **Alerting:** Comentado, no activo (ni Alertmanager ni rules)
- **Retención:** Default de Prometheus (sin configuración explícita)

### Grafana (v12.4.2)
- **Datasources:** Prometheus (`prometheus.monitoring.svc.cluster.local:9090`) + Loki (`loki.monitoring.svc.cluster.local:3100`)
- **Auth:** OIDC via Authelia, login form desactivado
- **DB:** PostgreSQL (`postgres.databases.svc.cluster.local`)
- **SMTP:** Configurado vía smtp-relay interno

### Exporters (no se tocan en la migración)
- **node-exporter** v1.10.2 — DaemonSet, host network, puerto 9100
- **kube-state-metrics** v2.18.0 — Deployment, puerto 8080
- **smartctl-exporter** v0.14.0 — DaemonSet, privileged, puerto 9633
- **nut-exporter** 3.2.5 — DaemonSet, host network, puerto 9199

### Loki + Promtail (no se tocan)
- Loki v3.6.8 — filesystem storage, 7 días retención
- Promtail v3.6.7 — DaemonSet, recoge pods + systemd journal + samba logs

---

## Decisiones tomadas

1. **Scrape interval** → **30s** (bajado desde 5s)
   - 5s es excesivamente agresivo para un homelab; genera volumen de samples innecesario y machaca disco/CPU.
   - 30s es suficiente granularidad para debugging y dashboards. El default de Prometheus es 15s; 30s maximiza el ahorro sin perder utilidad.
   - Se cambia *antes* de migrar (Fase 0) para no mezclar variables y tener una baseline limpia para comparar ambos sistemas.

2. **Datos históricos** → **Migrar con `vmctl` vía API remota** (los últimos ~15 días de Prometheus)
   - La retención actual de Prometheus es ~15 días (default). Perder ese histórico al migrar sería inaceptable; queremos continuidad en los dashboards.
   - `vmctl prometheus --prom-url=http://...` importa directamente desde la API de Prometheus, sin necesidad de snapshot ni `--web.enable-admin-api`.

3. **Arquitectura** → **Single-binary** (single-node homelab, no necesita cluster)
   - La arquitectura cluster de VM (vmagent + vmstorage + vmselect + vminsert) solo tiene sentido con múltiples nodos y alta disponibilidad.
   - En un NAS single-node, el single-binary hace scrape + storage + query todo en uno, minimizando complejidad operacional.

4. **Alerting** → **Otra tarea** (no mezclar migración con funcionalidad nueva)
   - Hoy no hay alerting activo (Alertmanager y rules están comentados en Prometheus).
   - Mezclar migración de stack con funcionalidad nueva aumenta el riesgo y dificulta el troubleshooting.

5. **Retención** → **`-retentionPeriod=100y`** (~4 GB/año sin downsampling, asumible en el NAS)
   - Sin licencia Enterprise, no hay downsampling nativo. Pero la compresión de VM (~0.4 bytes/sample) hace que los datos raw a 30s ocupen ~4 GB/año con ~10k series.
   - 40 GB en 10 años es despreciable en un NAS con varios TB disponibles.
   - **Importante:** el default de `-retentionPeriod` es 31 días, no infinito. Hay que ponerlo explícitamente.

6. **Downsampling** → **Tarea separada (DRAFT-2)**, pendiente de licencia Enterprise gratuita para homelab
   - El downsampling (`-downsampling.period`) es exclusivo de VM Enterprise.
   - Se ha solicitado licencia gratuita para homelab a VictoriaMetrics (precedente: [issue #5278](https://github.com/VictoriaMetrics/VictoriaMetrics/issues/5278) donde ofrecieron licencia personal gratis).
   - Si la obtenemos, se activa con un solo flag. Si no, ~4 GB/año es asumible sin downsampling.

7. **Datasource Grafana** → **Mantener nombre "Prometheus"** y solo cambiar la URL, para no romper dashboards
   - Los dashboards de Grafana referencian el datasource por nombre. Si cambiamos el nombre, hay que editar todos los dashboards.
   - VM expone una API compatible con Prometheus, así que el datasource tipo `prometheus` funciona directamente — solo hay que cambiar la URL.
   - **Nota:** la URL puede necesitar el path `/prometheus/` (ej. `http://host:8428/prometheus/`), aunque la raíz también expone `/api/v1/query`.

8. **Resource limits** → **Sin limits inicialmente**, se ajustarán en tarea separada
   - VM con ~10k series a 30s debería consumir ~256-512 MB RAM. No es necesario restringir desde el primer día.
   - Queremos observar el consumo real antes de poner limits que podrían causar OOMKills innecesarios durante la estabilización.
   - Se creará tarea separada para ajustar requests/limits una vez tengamos datos de consumo real.

9. **Migración de datos** → **Vía API remota** (sin snapshot)
   - `vmctl prometheus --prom-url=http://...` importa directamente desde la API de Prometheus sin necesidad de snapshot.
   - Evita habilitar `--web.enable-admin-api`, no duplica datos en disco, y simplifica la Fase 2.
   - Para ~15 días de datos, la importación vía API remota es suficientemente rápida.

10. **Backups** → **Otra tarea** (no mezclar con la migración)
    - VictoriaMetrics tiene `vmbackup`/`vmrestore` para backups nativos.
    - El hostPath `/data/victoriametrics/data` se beneficia del backup a nivel de filesystem que ya exista en el NAS.
    - Se abordará en tarea separada una vez la migración esté estabilizada.

11. **Labels ArgoCD de exporters** → **`monitoring-exporters`**
    - Verificado con `kubectl`: los DaemonSets node-exporter, smartctl-exporter, nut-exporter y el Deployment kube-state-metrics (+ sus Services) tienen todos `app: prometheus`.
    - Si ArgoCD elimina la app `prometheus` sin re-etiquetar, haría prune de todos estos recursos → pérdida total de monitorización.
    - El nuevo label `monitoring-exporters` es agnóstico del TSDB (no atado a "prometheus" ni a "victoriametrics"), lo que evita re-etiquetar en futuras migraciones.
    - **Crítico:** re-etiquetar y sincronizar ArgoCD **antes** de cualquier otro cambio (Fase 0, pasos 3-4).

12. **Security context de VM** → **Sin securityContext restrictivo** (corre como root)
    - Verificado con `docker inspect victoriametrics/victoria-metrics:latest`: el campo `User` está vacío → corre como **root (UID 0)** por defecto.
    - No necesita `fsGroup` ni `runAsUser` especial. El hostPath `/data/victoriametrics/data` será accesible sin problemas.
    - Prometheus usa `fsGroup: 65534` (nobody), pero VM no tiene esa restricción.
    - **Nota:** la versión actual de VM es **v1.138.0** (2026-03-13).

## Incertidumbres pendientes

1. **Compatibilidad de dashboards Grafana** — MetricsQL es superset de PromQL, pero `rate()` puede dar valores marginalmente distintos en bordes de ventana (tolerancia ≤5%). Se validará en Fase 3 con criterios cuantitativos.

---

## Ficheros clave afectados

- `lib/monitoring/prometheus/prometheus.libsonnet` — a reemplazar
- `lib/monitoring/grafana/grafana.libsonnet` — actualizar datasource (solo si cambia el nombre del service)
- `environments/monitoring/main.jsonnet` — recomponer con nuevo módulo
- `environments/versions.json` — añadir versión de VictoriaMetrics, quitar Prometheus
<!-- SECTION:NOTES:END -->
