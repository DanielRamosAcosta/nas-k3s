---
id: NASKS-17
title: Migrar a Sealed Secrets para poder usar secrets en CI
status: Done
assignee: []
created_date: '2026-03-15 17:48'
updated_date: '2026-03-15 21:42'
labels:
  - infrastructure
  - security
  - ci
dependencies: []
priority: medium
ordinal: 250
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Migración completa de todos los servicios (~18) de legacy age-encrypted secrets.json a Bitnami Sealed Secrets. 33 SealedSecrets desplegados en 6 namespaces, todos synced. Se usó scope cluster-wide para secretos compartidos (DB passwords, SMTP) y strict para secretos propios de cada servicio. lib/secrets.json no se tocó (parallel change). También se refactorizó invidious para separar config pública de secretos (patrón jq merge como immich), y se centralizaron imágenes hardcodeadas en versions.json.
<!-- SECTION:FINAL_SUMMARY:END -->
