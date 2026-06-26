---
id: NASKS-74
title: Añadir git hook que ejecute los checks de CI localmente antes de pushear
status: To Do
assignee: []
created_date: '2026-06-26 16:00'
labels:
  - ci
  - dx
  - tooling
dependencies: []
references:
  - .github/workflows/validate.yml
priority: medium
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Un git hook versionado en el repo que ejecute los mismos pasos que el workflow `validate.yml` (`tk fmt --test` + `tk eval` de todos los entornos) antes de cada commit/push, para detectar errores de formato y de compilación en local en vez de gastar una ronda de CI.

## 🎯 Contexto funcional

Surge de una retrospectiva: al implementar NASKS-71 (CouchDB), un push falló en CI únicamente por formato (`tk fmt --test` detectó el `.libsonnet` editado a mano sin formatear), obligando a un commit `style:` y una ronda extra de CI. Estos fallos son detectables en local con los mismos comandos que corre el CI; un hook los atrapa antes de pushear y elimina esa fricción recurrente (el repo es 100% Jsonnet/Tanka, así que el patrón se repite en cada cambio).

## ⚙️ Contexto técnico

`validate.yml` corre, en cada push a `main`: `tk fmt --test environments/ lib/` y un bucle `tk eval` sobre cada `environments/*/`. El hook debe espejar esos dos pasos. Consideraciones:

- **Versionado, no en `.git/` local**: usar `core.hooksPath` apuntando a un directorio del repo (p. ej. `.githooks/`) para que el hook se comparta y se versione.
- **Activación de un solo comando**: documentar el setup (`git config core.hooksPath .githooks`), idealmente sin dependencias nuevas más allá de las ya usadas (`tk`, `jb`).
- **Rendimiento**: saltar el hook (exit 0 rápido) si el commit/push no toca `lib/` ni `environments/`, para no penalizar commits no-Jsonnet.
- **pre-commit vs pre-push**: a decidir en el plan (pre-push es más barato porque corre una vez por push, no por commit; pre-commit da feedback antes). 
- **Mensaje de error accionable**: si `tk fmt --test` falla, indicar el archivo y sugerir `tk fmt environments/ lib/`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 El hook está versionado en el repo (p. ej. .githooks/) y se activa con un único comando documentado (git config core.hooksPath ...), sin dependencias nuevas más allá de tk/jb
- [ ] #2 El hook ejecuta tk fmt --test environments/ lib/ y aborta el commit/push si hay archivos sin formatear, con un mensaje que indique el archivo y sugiera tk fmt environments/ lib/
- [ ] #3 El hook ejecuta tk eval sobre cada entorno de environments/*/ y aborta si alguno no compila (espejo del job validate)
- [ ] #4 El hook hace exit 0 rápido cuando el commit/push no toca lib/ ni environments/ (no penaliza commits no-Jsonnet)
- [ ] #5 Documentado en el repo (README o CLAUDE.md) cómo activarlo y qué comprueba
<!-- AC:END -->
