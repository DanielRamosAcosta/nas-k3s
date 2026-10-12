---
title: "Imagen propia de seerr con OIDC (PR 2715)"
status: Done
priority: 2
labels: [seerr, oidc, ci]
parent:
references:
  - "https://github.com/seerr-team/seerr/pull/2715"
  - "https://github.com/DanielRamosAcosta/seerr"
created_date: 2026-10-12 09:55
---

## Description

## 📌 TLDR

Probar el soporte de OpenID Connect de seerr (PR #2715, aún abierto y desde un fork) desplegándolo en el homelab. Como seerr no publica imágenes para PRs de forks, construimos nuestra propia imagen del HEAD del PR vía GitHub Actions en un fork propio y la publicamos en `ghcr.io/danielramosacosta/seerr`.

## 🎯 Contexto funcional

El PR #2715 ("feat: initial support for OpenID Connect authentication") añade login OIDC a seerr. Interesa integrarlo con nuestra Authelia como el resto de servicios. Al estar abierto y venir de un fork (`michaelhthomas/seerr:feat/oidc-login-basic`), el CI de seerr salta los jobs de build/publish de imagen, así que no hay tag `sha-*`/RC oficial. El único preview existente (`seerr/seerr:preview-new-oidc`) está construido de un commit antiguo (`2d1a2ed`, ~sep) que no está en el HEAD actual del PR, así que no sirve para probar los fixes de octubre.

## ⚙️ Contexto técnico

- Fork del fork del autor → `DanielRamosAcosta/seerr` (misma network, rama `feat/oidc-login-basic` @ `2e52312`).
- Workflow propio en el fork (`.github/workflows/homelab-image.yml`) que construye el `Dockerfile` existente en `linux/amd64` (único nodo del clúster, `nixos` amd64) y lo publica en `ghcr.io/danielramosacosta/seerr` usando el `GITHUB_TOKEN` automático (packages: write). Build-args `COMMIT_TAG` y `BUILD_VERSION` como hace el CI original.
- Paquete ghcr **público** → k3s tira sin imagePullSecret.
- Despliegue vía el patrón Tanka/Jsonnet del repo (nuevo módulo en `lib/` + versión en `versions.json` + Application de ArgoCD por `u.labelApp()`).
- Rehacer la imagen cuando el PR reciba nuevos commits = re-lanzar el workflow.

## Acceptance Criteria

- [x] #1 Fork `michaelhthomas/seerr` en `DanielRamosAcosta/seerr` con la rama del PR disponible
- [x] #2 Workflow de GitHub Actions en el fork que construye el `Dockerfile` (linux/amd64) y publica en `ghcr.io/danielramosacosta/seerr`
- [x] #3 Imagen publicada y paquete ghcr marcado como público (pull sin credenciales)

El despliegue en el clúster se traslada a la tarea [[Desplegar seerr en el NAS con OIDC]].

## Implementation Plan

## Implementation Notes

- Imagen publicada: `ghcr.io/danielramosacosta/seerr:oidc-pr2715` (linux/amd64, construida 2026-10-12 del commit `2e52312`, HEAD del PR #2715).
- Fork: `DanielRamosAcosta/seerr`, rama `homelab-build` (= `feat/oidc-login-basic` + workflow). Para reconstruir tras nuevos commits del PR: rebasar `homelab-build` sobre la rama del PR y re-lanzar el workflow (`gh workflow run "Homelab image" --repo DanielRamosAcosta/seerr --ref homelab-build`).
- Paquete marcado público desde la UI de GitHub → k3s tira sin imagePullSecret.
