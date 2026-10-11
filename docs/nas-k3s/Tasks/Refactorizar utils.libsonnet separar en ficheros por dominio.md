---
title: 'Refactorizar utils.libsonnet: separar en ficheros por dominio'
status: Done
created_date: '2026-03-16 07:25'
labels:
  - infrastructure
  - refactor
  - dx
dependencies: []
references:
  - lib/utils.libsonnet
priority: 3
---

## Description

El fichero `lib/utils.libsonnet` tiene 337 líneas y contiene helpers de dominios muy distintos (PV/PVC, secrets, config maps, ingress routes, RBAC, volume mounts, Traefik middleware). A medida que se añadan más helpers (probes, etc.) se volverá inmanejable.

Plan:
1. Separar en ficheros por dominio dentro de `lib/utils/` (ej: `pv.libsonnet`, `sealedSecret.libsonnet`, `ingressRoute.libsonnet`, `configMap.libsonnet`, etc.)
2. El fichero `utils.libsonnet` pasa a ser un barrel que importa y re-exporta todos los módulos
3. Los consumidores siguen usando `import 'utils.libsonnet'` sin cambios — refactor transparente
4. Validar con `tk eval` que no se rompe nada

## Acceptance Criteria
- [x] #1 utils.libsonnet separado en ficheros por dominio dentro de lib/utils/
- [x] #2 utils.libsonnet actúa como barrel file que re-exporta todo
- [x] #3 Ningún consumidor necesita cambiar sus imports
- [x] #4 tk eval compila sin errores para todos los environments

## Final Summary

PR #16: Split utils.libsonnet into 12 domain modules in lib/utils/, restructured lib/ into namespace/app/ directories matching ArgoCD, removed 14 unused functions and 3 dead reference files (2980 lines). All verified with golden master scripts.
