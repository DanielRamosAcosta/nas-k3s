---
id: NASKS-89
title: Actualizar servidor de Minecraft a 26.3 (Wilderness Bound)
status: In Progress
assignee: []
created_date: '2026-09-19 06:45'
updated_date: '2026-09-19 06:45'
labels: []
dependencies: []
references:
  - 'https://minecraft.wiki/w/Java_Edition_26.3'
  - 'https://papermc.io/downloads/paper'
  - 'https://fill.papermc.io/v3/projects/paper/versions/26.3/builds'
modified_files:
  - lib/games/minecraft/minecraft.libsonnet
priority: medium
type: chore
ordinal: 86000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Subir el servidor de Minecraft de Paper 26.2 a **26.3** ("Wilderness Bound", publicada el 15-sep-2026), usando el último build experimental de Paper (build 19, canal ALPHA).

## 🎯 Contexto funcional

Mojang publicó Minecraft 26.3 el 15-sep-2026. Nuestro servidor va una versión por detrás (26.2). Se quiere subir a la última versión para disponer del nuevo contenido (bioma *dappled forest*, etc.).

## ⚙️ Contexto técnico

- Config en `lib/games/minecraft/minecraft.libsonnet` (`configEnv`).
- Cambios: `VERSION: 26.2 → 26.3` y `PAPER_BUILD: 65 → 19`.
- El canal ya es `experimental`, coherente con que Paper 26.3 solo tiene builds ALPHA por ahora (no hay build estable todavía).
- La imagen `itzg/minecraft-server:java25` ya cumple el requisito de Java 25 de 26.3 → no hace falta cambiar imagen.
- Despliegue vía GitOps (ArgoCD auto-sync); el StatefulSet se reinicia al cambiar el spec del pod.
- Riesgo: build alpha reciente, posible inestabilidad. Backup diario automático a las 05:00 UTC en `/cold-data/minecraft` como red de seguridad.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 El servidor de Minecraft corre la versión 26.3
- [ ] #2 PAPER_BUILD apunta al último build experimental de Paper para 26.3 (build 19)
- [ ] #3 El servidor arranca correctamente y es accesible (probe TCP 25565 en verde, mundo carga)
<!-- AC:END -->
