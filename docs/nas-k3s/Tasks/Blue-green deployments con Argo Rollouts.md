---
title: Blue-green deployments con Argo Rollouts
status: Done
created_date: '2026-03-15 23:55'
labels:
  - infrastructure
  - reliability
dependencies:
  - "[[Añadir healthchecks (liveness readiness probes) a todos los servicios]]"
  - "[[Alertado de despliegues fallidos]]"
priority: 3
ordinal: 0.00095367431640625
---

## Description

Instalar Argo Rollouts y migrar los servicios de Deployment/StatefulSet a Rollout con estrategia blue-green.

Plan:
1. Instalar Argo Rollouts controller en el cluster (nuevo environment en Tanka).
2. Migrar servicios progresivamente de Deployment a Rollout con estrategia blue-green.
3. Configurar activeService/previewService para cada servicio.
4. Integrar con ArgoCD para que los rollouts se gestionen via GitOps.

La nueva versión se levanta en paralelo, se valida con readinessProbe, y solo entonces se hace el switch. Si no arranca, no promueve y se queda con la versión anterior.

## Acceptance Criteria
- [ ] #1 Argo Rollouts controller instalado y gestionado via Tanka
- [ ] #2 Al menos un servicio migrado a Rollout con estrategia blue-green
- [ ] #3 Rollback automático funciona cuando la nueva versión no pasa healthchecks
- [ ] #4 Integrado con ArgoCD (sync/gestión via GitOps)
