---
id: NASKS-42
title: Borrar Gitea completamente del cluster
status: Done
assignee: []
created_date: '2026-03-22 00:14'
updated_date: '2026-03-22 00:47'
labels:
  - cleanup
  - refined
dependencies: []
references:
  - lib/media/gitea/gitea.libsonnet
  - lib/databases/postgres/postgres.libsonnet
  - lib/auth/authelia/authelia.config.yml
  - environments/media/main.jsonnet
priority: medium
ordinal: 0.06103515625
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Eliminar completamente Gitea del cluster y del repositorio IaC, incluyendo base de datos, cliente OIDC, y todas las referencias.

## Archivos a eliminar
- `lib/media/gitea/gitea.libsonnet` — módulo principal
- `lib/media/gitea/gitea.secrets.json` — secrets cifrados
- `.golden/*gitea*` — 7 golden files
- `dist/media/*gitea*` — 5 manifiestos exportados

## Archivos a modificar
- `environments/media/main.jsonnet` — quitar import y instancia de `gitea`
- `lib/versions.json` — quitar entrada `gitea`
- `lib/databases/postgres/postgres.libsonnet` — quitar `userGitea` (Job + SealedSecret)
- `lib/databases/postgres/postgres.secrets.json` — quitar `userGitea`
- `lib/auth/authelia/authelia.config.yml` — quitar bloque OIDC client de Gitea (~líneas 160-183)
- `lib/auth/authelia/authelia.secrets.json` — quitar env vars `GITEA_CLIENT_ID` y `GITEA_CLIENT_SECRET_DIGEST`

## Flujo de ejecución
1. Hacer todos los cambios en el repo (eliminar + modificar archivos)
2. Commit + push → CI regenera manifests branch
3. ArgoCD pruna la Application de gitea → el finalizer `resources-finalizer.argocd.argoproj.io` hace cascade delete de todos los recursos K8s (StatefulSet, Service, ConfigMap, SealedSecrets, IngressRoute, RBAC)
4. DROP DATABASE gitea + DROP USER gitea en Postgres
5. **Manual**: borrar `/cold-data/gitea/data` del NAS
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No queda ninguna referencia a gitea en lib/, environments/, ni versions.json
- [ ] #2 Cliente OIDC de Gitea eliminado de Authelia (config + secrets)
- [ ] #3 Usuario y Job de Postgres para Gitea eliminados
- [ ] #4 Golden files y dist de Gitea eliminados
- [ ] #5 tk eval environments/media y tk eval environments/databases compilan sin error
- [ ] #6 ArgoCD ha prunado la Application y los recursos K8s de gitea
- [ ] #7 DROP DATABASE gitea + DROP USER gitea ejecutados en Postgres
- [ ] #8 Datos de /cold-data/gitea/data borrados del NAS
<!-- AC:END -->
