---
id: NASKS-20
title: Migrar de Kubernetes Dashboard a Headlamp
status: To Do
assignee: []
created_date: '2026-03-15 21:04'
updated_date: '2026-03-16 11:05'
labels:
  - infra
  - migración
dependencies: []
references:
  - 'https://github.com/kubernetes/dashboard'
  - 'https://github.com/headlamp-k8s/headlamp'
priority: medium
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Kubernetes Dashboard fue archivado en enero de 2026 y ya no se mantiene. El proyecto recomienda migrar a **Headlamp** como alternativa activamente mantenida bajo sig-ui.

Actualmente tenemos el chart de Kubernetes Dashboard vendorizado en `charts/kubernetes-dashboard/`. Hay que:

1. Evaluar Headlamp y su método de instalación (Helm chart disponible)
2. Desplegar Headlamp en el cluster con Tanka
3. Configurar IngressRoute con Traefik y autenticación Authelia
4. Verificar funcionalidad equivalente
5. Eliminar el chart vendorizado de Kubernetes Dashboard y su configuración asociada
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Headlamp desplegado y accesible via IngressRoute
- [ ] #2 Autenticación con Authelia configurada
- [ ] #3 Chart vendorizado de kubernetes-dashboard eliminado
- [ ] #4 Entorno de Tanka actualizado sin referencias a kubernetes-dashboard
<!-- AC:END -->
