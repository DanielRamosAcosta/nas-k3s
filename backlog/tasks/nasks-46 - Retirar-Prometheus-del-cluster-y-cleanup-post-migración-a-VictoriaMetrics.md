---
id: NASKS-46
title: Retirar Prometheus del cluster y cleanup post-migración a VictoriaMetrics
status: To Do
assignee: []
created_date: '2026-03-28 14:14'
labels:
  - monitoring
  - cleanup
dependencies:
  - NASKS-45
references:
  - lib/monitoring/prometheus/prometheus.libsonnet
  - environments/monitoring/main.jsonnet
  - lib/versions.json
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tras completar la migración a VictoriaMetrics (NASKS-45 Fases 0-4), Prometheus sigue corriendo como fallback. Después de un periodo de gracia (~1 semana desde 2026-03-28), retirar Prometheus y limpiar los recursos asociados.

## Plan

1. Verificar que Grafana lleva ≥1 semana funcionando sin problemas con VictoriaMetrics
2. Retirar Prometheus del `environments/monitoring/main.jsonnet`
3. Sincronizar ArgoCD — la app `prometheus` tiene auto-prune, así que eliminará los recursos automáticamente. Verificar que no queden recursos huérfanos.
4. Borrar `lib/monitoring/prometheus/`
5. Quitar imagen de Prometheus de `lib/versions.json`
6. Commit y deploy
7. Limpiar `/data/prometheus/data` del NAS
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Prometheus retirado del environment de monitoring
- [ ] #2 ArgoCD sincroniza correctamente sin Prometheus
- [ ] #3 lib/monitoring/prometheus/ borrado
- [ ] #4 Imagen de Prometheus eliminada de versions.json
- [ ] #5 Directorio /data/prometheus/data limpiado del NAS
<!-- AC:END -->
