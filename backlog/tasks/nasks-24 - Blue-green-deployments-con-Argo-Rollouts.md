---
id: NASKS-24
title: Blue-green deployments con Argo Rollouts
status: To Do
assignee: []
created_date: '2026-03-15 23:55'
updated_date: '2026-03-16 11:05'
labels:
  - infrastructure
  - reliability
dependencies:
  - NASKS-22
  - NASKS-23
priority: low
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Instalar Argo Rollouts y migrar los servicios de Deployment/StatefulSet a Rollout con estrategia blue-green.

Plan:
1. Instalar Argo Rollouts controller en el cluster (nuevo environment en Tanka).
2. Migrar servicios progresivamente de Deployment a Rollout con estrategia blue-green.
3. Configurar activeService/previewService para cada servicio.
4. Integrar con ArgoCD para que los rollouts se gestionen via GitOps.

La nueva versión se levanta en paralelo, se valida con readinessProbe, y solo entonces se hace el switch. Si no arranca, no promueve y se queda con la versión anterior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Argo Rollouts controller instalado y gestionado via Tanka
- [ ] #2 Al menos un servicio migrado a Rollout con estrategia blue-green
- [ ] #3 Rollback automático funciona cuando la nueva versión no pasa healthchecks
- [ ] #4 Integrado con ArgoCD (sync/gestión via GitOps)
<!-- AC:END -->
