---
id: NASKS-19
title: Migrar de Gitea a repositorios Git nativos por SSH
status: To Do
assignee: []
created_date: '2026-03-15 20:43'
updated_date: '2026-03-16 11:05'
labels:
  - infra
  - migración
  - git
dependencies: []
priority: medium
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Eliminar el servicio Gitea del cluster y reemplazarlo por repositorios bare de Git accesibles vía SSH nativo en el NAS.

## Contexto
Git sobre SSH nativo es suficiente para nuestras necesidades (push/pull privado). Gitea añade complejidad innecesaria (base de datos, ingress, recursos del cluster) sin que usemos sus funcionalidades extra (issues, PRs, CI/CD web).

## Plan de migración
1. Inventariar todos los repos alojados en Gitea
2. Crear directorio base para repos bare en el NAS (ej: `/data/git/`)
3. Clonar cada repo de Gitea como bare al NAS (`git clone --bare`)
4. Verificar integridad de cada repo migrado (branches, tags, historial)
5. Actualizar los remotes en todas las máquinas locales para apuntar a `ssh://user@nas/data/git/repo.git`
6. Confirmar que push/pull funcionan correctamente en todos los repos
7. Eliminar los manifiestos de Gitea del cluster (lib/, environments/, etc.)
8. Limpiar datos antiguos de Gitea (PV, base de datos si aplica)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Todos los repos de Gitea migrados como bare repos en el NAS
- [ ] #2 Remotes actualizados en todas las máquinas de desarrollo
- [ ] #3 Push/pull funcional vía SSH nativo para todos los repos
- [ ] #4 Manifiestos de Gitea eliminados del repositorio IaC (lib/, environments/)
- [ ] #5 Gitea ya no corre en el cluster
- [ ] #6 No hay pérdida de historial, branches ni tags en ningún repo
<!-- AC:END -->
