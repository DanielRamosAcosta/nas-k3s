---
id: NASKS-23
title: Alertado de despliegues fallidos
status: Done
assignee: []
created_date: '2026-03-15 23:55'
updated_date: '2026-03-18 21:11'
labels:
  - infrastructure
  - reliability
  - monitoring
dependencies:
  - NASKS-22
priority: medium
ordinal: 31.25
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Configurar alertas cuando un despliegue falla o un servicio queda en estado degradado tras un sync de ArgoCD.

Opciones:
- ArgoCD Notifications para enviar alertas (Telegram, Discord, email) cuando una app pasa a Degraded/OutOfSync.
- Alertmanager rules en Prometheus para detectar pods en CrashLoopBackOff o restarts frecuentes.

Esto es prerequisito para Argo Rollouts, ya que sin alertado no nos enteramos de fallos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Se recibe alerta cuando un pod entra en CrashLoopBackOff o no pasa readinessProbe
- [ ] #2 Se recibe alerta cuando ArgoCD detecta una app Degraded tras sync
- [ ] #3 Canal de notificación configurado (Telegram, Discord u otro)
<!-- AC:END -->
