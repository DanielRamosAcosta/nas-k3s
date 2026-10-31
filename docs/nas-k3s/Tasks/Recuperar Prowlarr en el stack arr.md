---
title: "Recuperar Prowlarr en el stack arr"
status: Done
priority: 2
labels: [arr, indexers, prowlarr]
parent:
references: []
created_date: 2026-10-31 18:57
---

## Description

## 📌 TLDR

Volver a desplegar Prowlarr (gestor/agregador de indexers) en el namespace `arr`. Existió en el repo pero se perdió en la gran reestructuración `bfdda2c5 "add lots of stuff"` (que quitó el prefijo `tanka/`). El hostPath `/data/arr/prowlarr` **sobrevivió intacto** en el NAS (`prowlarr.db`, `config.xml`, `Definitions/`), así que al levantarlo recuperamos la config e indexers tal como estaban (última actividad 25 ene 2026).

## 🎯 Contexto funcional

Hoy el stack *arr es "pelado": Radarr/Sonarr/Lidarr conectan sus indexers a mano, sin capa de agregación. Prowlarr centraliza los indexers (incluido norznab) y los sincroniza a los tres *arr de golpe, y habilita añadir fuentes nuevas (p. ej. una definición Cardigann de Torrentio) sin tocar cada *arr. Disparador: duda sobre integrar Radarr con Torrentio.

## ⚙️ Contexto técnico

- Nuevo módulo `lib/arr/prowlarr/prowlarr.libsonnet` siguiendo el patrón moderno de `radarr`/`sonarr`: `deployment + service + configEnv`, sin IngressRoute (los *arr no se exponen por Traefik en este repo) ni SealedSecret.
- Imagen `ghcr.io/hotio/prowlarr`, puerto `9696`, probe `/ping`, único volumen `config` → hostPath `/data/arr/prowlarr`.
- `PUID=1000 PGID=100` (el owner del hostPath es `1000:100`), `TZ=Atlantic/Canary`, `PROWLARR__LOG__CONSOLEFORMAT=Clef` (consistente con el resto de *arr).
- Versión fijada `release-2.7.0.5723` (último tag semver de hotio; los `release-<hash>` se descartan).
- Conectado en `environments/arr/main.jsonnet`; `u.Environment()` estampa `labelApp` (→ ArgoCD crea su Application) y la anotación de Reloader automáticamente.

## Acceptance Criteria

- [x] #1 Módulo `lib/arr/prowlarr/prowlarr.libsonnet` con el patrón moderno del repo
- [x] #2 `prowlarr` añadido a `lib/versions.json` (`ghcr.io/hotio/prowlarr` · `release-2.7.0.5723`)
- [x] #3 `prowlarr` conectado en `environments/arr/main.jsonnet`
- [x] #4 `tk eval environments/arr` compila sin errores y el Deployment sale con `labelApp=prowlarr` y `reloader=true`
- [x] #5 Prowlarr arranca reutilizando `/data/arr/prowlarr` — config e indexers previos intactos

## Definition of Done

- [x] #1 desplegar con /deploy

## Implementation Plan

1. Recuperar el módulo del historial (`git show bfdda2c5~1:tanka/lib/arr/prowlarr.libsonnet`) como referencia y reescribirlo al patrón actual.
2. Añadir `prowlarr` a `lib/versions.json`.
3. Conectar `prowlarr.new()` en `environments/arr/main.jsonnet`.
4. Validar con `tk eval environments/arr`.
5. `/deploy` y verificar en ArgoCD/Loki que el pod arranca y lee la DB existente.

## Implementation Notes

- Desplegado vía PR #330 (squash merge). ArgoCD creó la Application `prowlarr` (Synced/Healthy) y el pod arrancó **Running 1/1, 0 restarts**, reutilizando `/data/arr/prowlarr` (DB migrada a versión 44, Sqlite 3.53.4).
- **La DB no tenía indexers configurados** — `Definitions/` solo contenía las plantillas de tipos que trae Prowlarr de serie, no indexers del usuario. Prowlarr arranca con 0 indexers (health check rojo "No indexers enabled", esperado).
- **Apps**: solo estaba configurada **Sonarr** (no Radarr ni Lidarr). Su API key había quedado obsoleta tras recrearse la config de Sonarr → `401 Unauthorized`. Reconfigurada vía la UI (Chrome): la key se copió del `config.xml` de Sonarr directamente al portapapeles y se pegó en el campo, sin exponerla en texto. Verificado: health check de 401 desaparecido y cero `401/unauthorized` en Loki tras el guardado.
- Acceso a la UI por `kubectl port-forward` (no hay IngressRoute para los *arr; todos ClusterIP).
- Pendiente (fuera del alcance de esta tarea): añadir indexers (Torrentio, norznab) y, si se quiere sync a Radarr/Lidarr, añadirlas como Apps.

