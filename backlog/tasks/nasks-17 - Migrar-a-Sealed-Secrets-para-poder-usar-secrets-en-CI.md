---
id: NASKS-17
title: Migrar a Sealed Secrets para poder usar secrets en CI
status: In Progress
assignee: []
created_date: '2026-03-15 17:48'
updated_date: '2026-03-15 17:49'
labels:
  - infrastructure
  - security
  - ci
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Actualmente `lib/secrets.json` es un fichero plaintext gitignored, cifrado con age a `secrets.json.age`. Esto impide que CI pueda hacer `tk eval` porque no tiene acceso a los secrets.

Migrar a Sealed Secrets (o alternativa como SOPS) para que los secrets estén committeados de forma segura y CI pueda compilar los manifiestos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Secrets committeados de forma segura en el repo
- [ ] #2 CI puede hacer `tk eval` de todos los environments sin acceso a secrets plaintext
- [ ] #3 Despliegue sigue funcionando correctamente en el cluster
<!-- AC:END -->
