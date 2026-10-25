---
title: "Automerge de Renovate (digest/patch) + serializar push a manifests"
status: In Progress
priority: 2
labels:
  - ci
  - infrastructure
  - renovate
references:
  - "https://docs.renovatebot.com/configuration-options/#automerge"
created_date: 2026-10-25 14:10
---

## Description

## 📌 TLDR

Dejar de fusionar a mano la pila de PRs de Renovate: automergear los bumps de **digest y patch** cuando pasan CI, y **serializar** el push a la rama `manifests` para eliminar la carrera cuando se fusionan varias PRs casi a la vez.

## 🎯 Contexto funcional

Renovate abre muchas PRs de bumps de imágenes (`chore(deps)`) que se acumulan (10 abiertas en el momento de crear la tarea). Fusionarlas todas manualmente es tedioso. Además, cada merge a `main` dispara el workflow que publica a la rama `manifests`; dos merges seguidos provocan runs concurrentes que compiten por el `git push` a `manifests` (carrera conocida: el run perdedor falla por non-fast-forward).

Se descartó **GitHub Merge Queue**: para un repo de un solo mantenedor con bumps independientes de Renovate aporta más fricción (branch protection + required checks + trigger `merge_group`) que valor; su ventaja (evitar que la interacción de dos PRs rompa main) casi no aplica aquí.

## ⚙️ Contexto técnico

Estado de partida: `main` sin branch protection (merge directo), `allow_auto_merge` desactivado en el repo, `renovate.json` sin automerge, `validate.yml` sin `concurrency`.

Implementación:

1. **`renovate.json`** — `packageRule` con `matchUpdateTypes: ["digest", "patch"]`, `automerge: true`, `platformAutomerge: true`. Minor/major siguen manuales.
2. **`.github/workflows/validate.yml`** — añadir `concurrency: { group: "${{ github.workflow }}-${{ github.ref }}", cancel-in-progress: false }` para serializar los pushes a `manifests` en `main`.
3. **GitHub repo** (vía `gh api`) — activar `allow_auto_merge` y añadir branch protection ligera en `main` con el status check de `validate` como requerido, para que el automerge de Renovate espere a CI en lugar de fusionar a ciegas.

## Acceptance Criteria

- [ ] #1 Renovate automergea solo bumps de digest y patch (minor/major siguen manuales)
- [ ] #2 El push a la rama `manifests` queda serializado (concurrency group) — sin carrera al fusionar varias PRs
- [ ] #3 `main` con branch protection ligera: el check `validate` es requerido
- [ ] #4 `allow_auto_merge` activado en el repo
- [ ] #5 Verificado: una PR de Renovate digest/patch se fusiona sola tras pasar CI

## Implementation Plan

## Implementation Notes
