---
id: NASKS-1
title: Add alerting to monitoring stack
status: To Do
assignee: []
created_date: '2026-03-09 16:47'
updated_date: '2026-03-16 11:05'
labels:
  - monitoring
  - feature
  - kubernetes
dependencies: []
references:
  - tanka/lib/monitoring/prometheus.yml
  - tanka/lib/monitoring/prometheus.rules
  - tanka/lib/monitoring/loki.config.yml
  - tanka/lib/monitoring/promtail.config.yml
  - tanka/lib/monitoring/grafana.libsonnet
  - tanka/lib/monitoring/prometheus.libsonnet
priority: medium
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Montar alerting para el stack de monitorización. La infraestructura ya está parcialmente preparada — Prometheus tiene la config de alertmanager comentada y un archivo de reglas placeholder, y Loki también tiene la integración con alertmanager comentada. Hay que desplegar Alertmanager y configurar reglas de alerta para las métricas y logs que ya se están recopilando.

## Estado actual

**Lo que ya está corriendo:**
- Prometheus v3.7.3 scrapeando métricas cada 5s
- Grafana v12.3.1 con datasources de Prometheus + Loki
- Loki v3.5.7 + Promtail v3.5.7 para agregación de logs
- Node Exporter (CPU, memoria, disco, red)
- SMARTCTL Exporter (salud de discos)
- NUT Exporter (estado del SAI — Salicru)

**Lo que está preparado pero deshabilitado:**
- `prometheus.yml` tiene la URL de alertmanager comentada (`alertmanager.monitoring.svc:9093`)
- El archivo `prometheus.rules` existe pero no se carga (rule_files comentado)
- La config de Loki tiene la integración con alertmanager comentada

## Opciones de alerting

### Opción A: Alertmanager + reglas de Prometheus (recomendada)
Desplegar Alertmanager como nuevo servicio en el namespace monitoring. Descomentar la config existente de Prometheus y Loki. Definir reglas de alerta en Prometheus para alertas basadas en métricas. Es el enfoque estándar, ya parcialmente cableado.

- **Canales de notificación:** Email SMTP, Gotify (notificaciones push self-hosted), bot de Telegram, o Ntfy (pub/sub ligero)
- **Pros:** Integración nativa con Prometheus, ecosistema maduro, agrupación/silenciamiento/inhibición
- **Contras:** Otro servicio que mantener, config pesada en YAML

### Opción B: Alerting nativo de Grafana
Usar el sistema de alertas integrado de Grafana (disponible desde v9). Definir reglas de alerta directamente en la UI de Grafana o por provisioning. Soporta datasources de Prometheus y Loki.

- **Canales de notificación:** Mismas opciones (email, Gotify, Telegram, Ntfy, etc.) vía contact points de Grafana
- **Pros:** Una sola UI para dashboards + alertas, más fácil de gestionar para setups pequeños, puede alertar sobre métricas y logs
- **Contras:** Dependiente de la disponibilidad de Grafana, agrupación menos potente que Alertmanager

### Opción C: Híbrido (Alertmanager + alertas de Grafana)
Usar Alertmanager para alertas críticas de infraestructura (disco, SAI, nodo caído) vía reglas de Prometheus, y alertas de Grafana para alertas a nivel de aplicación o basadas en logs.

- **Pros:** Lo mejor de ambos mundos, separación de responsabilidades
- **Contras:** Más complejidad, dos sistemas de alertas que configurar

## Reglas de alerta sugeridas (independientemente de la opción)

**Críticas:**
- Nodo caído / inaccesible
- Fallo o pre-fallo SMART en disco
- SAI en batería / SAI offline
- Filesystem > 90% lleno
- API server de K3s inaccesible

**Warning:**
- Uso de CPU alto (sostenido > 80%)
- Uso de memoria alto (> 85%)
- Temperatura SMART de disco por encima del umbral
- Batería del SAI por debajo del 50%
- Filesystem > 75% lleno
- Pod en crash loop
- Container OOMKilled

**Info / Basadas en logs:**
- Fallos de autenticación en Samba (vía Loki)
- Intentos de login SSH (vía Loki/journal)
- Errores de componentes de K3s (vía Loki)
<!-- SECTION:DESCRIPTION:END -->
