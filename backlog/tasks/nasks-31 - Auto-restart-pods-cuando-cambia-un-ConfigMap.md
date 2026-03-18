---
id: NASKS-31
title: Auto-restart pods cuando cambia un ConfigMap
status: To Do
assignee: []
created_date: '2026-03-18 21:22'
updated_date: '2026-03-18 21:27'
labels:
  - improvement
  - infrastructure
dependencies: []
priority: low
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Actualmente cuando se cambia un ConfigMap, los pods dependientes no se reinician automáticamente y hay que hacer `kubectl rollout restart` manualmente.

## Opciones evaluadas

| | **Stakater Reloader** | **Hash annotation en Jsonnet** |
|---|---|---|
| **Qué es** | Controller que corre en el cluster | Patrón en el template del pod |
| **Cómo funciona** | Watch en ConfigMaps/Secrets → rollout automático | Hash del contenido como annotation → K8s detecta cambio en pod spec |
| **Instalación** | Deployment extra (Helm chart o manifest) | Cero — solo cambio en `utils.libsonnet` |
| **Recursos** | Pod 24/7 (~20-30MB RAM, CPU despreciable) | Nada extra en runtime |
| **Alcance** | Detecta cambios de cualquier origen (manual, kubectl, etc.) | Solo detecta cambios que pasen por Jsonnet/Tanka |
| **Configuración** | Annotation `reloader.stakater.com/auto: "true"` por Deployment | Automático si se mete en el helper |
| **Complejidad** | Otro servicio que mantener y actualizar | Cero overhead operacional |

Todos los cambios pasan por Jsonnet → Git → ArgoCD, así que el hash annotation cubriría el 100% de los casos sin añadir nada al cluster. Pero queda pendiente decidir la herramienta.
<!-- SECTION:DESCRIPTION:END -->
