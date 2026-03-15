---
id: NASKS-22
title: Añadir healthchecks (liveness/readiness probes) a todos los servicios
status: To Do
assignee: []
created_date: '2026-03-15 23:44'
labels:
  - infrastructure
  - reliability
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Actualmente ningún servicio tiene liveness, readiness ni startup probes configurados. Kubernetes solo detecta si el proceso está corriendo, pero no si la aplicación responde correctamente.

Plan:
1. Crear helpers en `utils.libsonnet` para facilitar añadir probes de forma consistente (HTTP, TCP, exec).
2. Añadir probes a cada servicio según su tipo (HTTP endpoint, puerto TCP, etc.).
3. Validar con `tk eval` que los manifiestos generados son correctos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Todos los Deployments/StatefulSets tienen al menos un readinessProbe configurado
- [ ] #2 Helper en utils.libsonnet para añadir probes de forma consistente
- [ ] #3 tk eval compila sin errores para todos los environments
<!-- AC:END -->
