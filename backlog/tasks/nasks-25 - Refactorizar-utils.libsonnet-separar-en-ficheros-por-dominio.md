---
id: NASKS-25
title: 'Refactorizar utils.libsonnet: separar en ficheros por dominio'
status: To Do
assignee: []
created_date: '2026-03-16 07:25'
labels:
  - infrastructure
  - refactor
  - dx
dependencies: []
references:
  - lib/utils.libsonnet
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
El fichero `lib/utils.libsonnet` tiene 337 líneas y contiene helpers de dominios muy distintos (PV/PVC, secrets, config maps, ingress routes, RBAC, volume mounts, Traefik middleware). A medida que se añadan más helpers (probes, etc.) se volverá inmanejable.

Plan:
1. Separar en ficheros por dominio dentro de `lib/utils/` (ej: `pv.libsonnet`, `sealedSecret.libsonnet`, `ingressRoute.libsonnet`, `configMap.libsonnet`, etc.)
2. El fichero `utils.libsonnet` pasa a ser un barrel que importa y re-exporta todos los módulos
3. Los consumidores siguen usando `import 'utils.libsonnet'` sin cambios — refactor transparente
4. Validar con `tk eval` que no se rompe nada
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 utils.libsonnet separado en ficheros por dominio dentro de lib/utils/
- [ ] #2 utils.libsonnet actúa como barrel file que re-exporta todo
- [ ] #3 Ningún consumidor necesita cambiar sus imports
- [ ] #4 tk eval compila sin errores para todos los environments
<!-- AC:END -->
