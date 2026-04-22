---
id: NASKS-55
title: Grafana dashboard para Crowdsec (agent + LAPI metrics)
status: To Do
assignee: []
created_date: '2026-04-22 20:36'
labels:
  - observability
  - grafana
  - crowdsec
  - followup-nasks-53
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

En NASKS-53 habilitamos `metrics.enabled: true` en el chart Crowdsec y el LAPI expone `/metrics` en el puerto 6060 del service `crowdsec-service.system` (más el agent en `crowdsec-agent-service`). VictoriaMetrics (scrape generalista) ya los está recogiendo.

Falta importar el dashboard oficial de Crowdsec en Grafana para ver:
- Decisions activas totales / por origen (community vs local)
- Alerts por scenario (top scenarios disparados)
- Requests procesadas por parser
- Estado del Hub (versiones de collections, última sync con CAPI)
- Rate de buckets creados/overflow (heat of attacks)
- Latencia de la LAPI

## Pasos

1. Abrir Grafana (`grafana.danielramos.me`) → Dashboards → New → Import.
2. Usar el ID del dashboard oficial de grafana.com (buscar "crowdsec" en la librería). Los más relevantes suelen ser:
   - `crowdsecurity/crowdsec` (dashboard del agent)
   - Algún community del LAPI
3. Source: el datasource Prometheus (VictoriaMetrics) que ya tiene Grafana.
4. Verificar que los paneles rellenan (labels esperados: `job="crowdsec"`, `instance=...`).
5. Si los labels no coinciden con los que VM inyecta, ajustar queries o añadir relabel rules en `VMServiceScrape` (requiere crearlo — actualmente no hay ServiceMonitor / VMServiceScrape dedicado).

## Trabajo opcional (si hace falta)

Hoy VM scrappea pods generalistas. Si las métricas de Crowdsec no aparecen, crear un `VMServiceScrape` apuntando al service `crowdsec-service` en `system`. Path `/metrics`, port `6060`.

## Acceptance criteria

- [ ] Dashboard Crowdsec importado en Grafana.
- [ ] Paneles con datos reales (no "No data").
- [ ] Al menos visible: decisions count, alerts rate, hub status.

## No scope

- AppSec / WAF metrics (no tenemos AppSec desplegado).
- Alertas Grafana sobre picos de attacks (follow-up separado si llega el día).
<!-- SECTION:DESCRIPTION:END -->
