---
title: "Configurar indexers en Prowlarr norznab y Torrentio"
status: Done
priority: 2
labels: [arr, indexers, prowlarr, torrentio, norznab]
parent: "[[Recuperar Prowlarr en el stack arr]]"
references: []
created_date: 2026-10-31 19:20
---

## Description

## 📌 TLDR

Poblar Prowlarr (que quedó operativo pero vacío tras recuperarlo) con dos indexers: **norznab** (indexer Torznab casero del usuario) como Generic Torznab, y **Torrentio** mediante una definición Cardigann custom. Torrentio se usará con **P2P directo** (sin debrid), asumiendo la exposición de IP.

## 🎯 Contexto funcional

Prowlarr centraliza los indexers y los sincroniza a Sonarr/Radarr/Lidarr. Tras la recuperación arrancó con 0 indexers (health check rojo). Añadir norznab (fuente ES: DonTorrent/MarcianoTorrent vía Tor) y Torrentio (fuente internacional/inglés amplia) da cobertura a las búsquedas de los *arr. Disparador: duda inicial sobre integrar Radarr con Torrentio.

## ⚙️ Contexto técnico

- **norznab**: añadir como **Generic Torznab** vía la UI de Prowlarr. Endpoint verificado: `http://norznab:3000` + API path `/api` (NO `/torznab/api`). `caps` y búsquedas responden **sin API key** (el campo del formulario de Prowlarr se rellena con un placeholder porque norznab lo ignora). Caps: movie-search (`tmdbid`) y tv-search (`q,tmdbid,rid,tvdbid,tvmazeid,season,ep`); categorías Movies (2000) y TV (5000).
- **Torrentio**: NO existe en las 656 definiciones integradas de Prowlarr → requiere una **definición Cardigann (YAML)** en `/config/Definitions/Custom/`. Para hacerlo GitOps (no a mano en el pod) se monta vía **ConfigMap** en `lib/arr/prowlarr/prowlarr.libsonnet` sobre `/config/Definitions/Custom/`, y Reloader reinicia el pod. Addon base `https://torrentio.strem.fun/` (protocolo torrent, magnets públicos).
- **Aviso debrid/P2P**: Torrentio entrega magnets pensados para debrid. Sin debrid, Radarr los manda al cliente torrent → descarga P2P con la IP del NAS (relevante por los bloqueos del ISP). Se asume conscientemente.
- Acceso a la UI por `kubectl port-forward` (los *arr son ClusterIP, sin IngressRoute).

## Acceptance Criteria

- [x] #1 norznab añadido como Generic Torznab (`http://norznab:3000`, path `/api`) con Test OK — **DESBLOQUEADO**: se arregló norznab para soportar `t=search` (norznab PR #18, imagen `main-a0ca064`, bump en nas-k3s PR #334). Test OK, añadido como indexer.
- [x] #2 Definición Cardigann de Torrentio montada vía ConfigMap en `prowlarr.libsonnet` (GitOps) y desplegada
- [x] #3 Torrentio añadido como indexer en Prowlarr con Test OK (P2P directo, sin debrid)
- [x] #4 Torrentio sincronizado a Sonarr vía Prowlarr (health check "No indexers enabled" resuelto; badge System 2→1)

## Implementation Plan

1. **norznab** — intentar añadir como Generic Torznab (`http://norznab:3000`, path `/api`). **BLOQUEADO**: norznab no implementa el modo genérico `t=search` (devuelve `error 201 Invalid parameters`), que Prowlarr exige en su validación → no deja guardar. Requiere fix en el repo de norznab (soportar `t=search`, aunque sea devolviendo RSS vacío). Fuera del alcance de este repo.
2. **Torrentio** — definición Cardigann de `dreulavelle/Prowlarr-Indexers` guardada en `lib/arr/prowlarr/definitions/torrentio.yml`.
3. Montarla GitOps: ConfigMap `torrentio-yml` + **initContainer** `install-definitions` (busybox) que la copia a `/config/Definitions/Custom/torrentio.yml` en el hostPath (evita el chown RO de hotio).
4. `/deploy` y verificar que el pod arranca y Prowlarr carga la definición.
5. Añadir Torrentio en la UI con `debrid_provider: none` (P2P directo) y Test OK.

## Implementation Notes

- **Torrentio**: desplegado (PR #331 definición + initContainer; PR #332 fix infohash). Añadido en la UI con `debrid_provider: none` (P2P) y Base Url `https://torrentio.strem.fun/`. Test OK, enabled, Movies+TV. Sincronizado a Sonarr (log `Searching indexer(s): [Torrentio] ... Categories: [5000]` sin errores). Health check "No indexers enabled" resuelto (badge System 2→1).
- **Fix infohash (PR #332)**: la definición de dreulavelle extrae el infohash del campo `url` (solo presente con debrid). En P2P, Torrentio devuelve `infoHash` directamente → se cambió `selector: url`+regex por `selector: infoHash`. Sin esto el Test fallaba con `Selector "url" didn't match JSON content`.
- **norznab — BLOQUEADO**: no implementa el modo genérico `t=search` (devuelve `error 201 Invalid parameters`), que Prowlarr exige en la validación del Generic Torznab → no deja guardar. `caps`, `t=movie` y `t=tvsearch` sí responden (sin API key). Radarr/Sonarr lo usan directamente porque llaman por `t=movie`/`t=tvsearch`, pero Prowlarr prueba `t=search`. **Fix pendiente en el repo de norznab**: soportar `t=search` (aunque devuelva RSS vacío). Fuera del alcance de este repo.
- **Pendiente para películas**: Torrentio es Movies+TV pero solo está sincronizado a Sonarr (TV). Radarr no está conectado como App en Prowlarr → para que Torrentio llegue a Radarr hay que añadir Radarr como App (requiere su API key). Lidarr igual (aunque Torrentio no da música).
- Limitación de Torrentio: busca por **IMDB ID**, no por texto libre (las búsquedas automáticas de Sonarr/Radarr sí pasan el imdbid). En búsqueda manual por texto cae a su película de validación (Fight Club).
- **Radarr conectado como App** en Prowlarr (API key copiada del config.xml al portapapeles, pegada sin exponer). E2E verificado: búsqueda interactiva de American Psycho en Radarr → Torrentio devolvió releases reales con seeders.
- **Milnueve (API) añadido como indexer** (tracker privado ES, `https://tracker.milnueve.cc/`). Cubre el hueco de castellano que pretendía norznab. API key generada en la cuenta del usuario (My Settings → Clave API) y pegada sin exponerla. Verificado: búsqueda "Interstellar" devuelve releases en **Spanish** con seeders. Sincronizado a Radarr/Sonarr (Full Sync).
- **Config de idioma de Torrentio** (PR #333): providers ES (mejortorrent, wolfmax4k, cinecalidad) + `language=spanish` para priorizar castellano manteniendo catálogo. Aun así Torrentio es flojo en ES; Milnueve es la fuente ES de verdad.
- **norznab desbloqueado** (norznab PR #18): se añadió el modo genérico Torznab `t=search` (nuevo `TorznabFunction.SEARCH` + `SearchRequestSchema` + `PerformSearchHandler`: sin query → item mock para el test del indexer; con `q` → `MovieAdapter.findMovie(q)`; declara `search` en caps). Imagen `ghcr.io/danielramosacosta/norznab:main-a0ca064`, bump en versions.json (nas-k3s PR #334). E2E verificado en Loki: Prowlarr→norznab `GET /api` responde 200 (antes error 201), test pasa con el mock, búsquedas devuelven RSS sin error.
- **Decisión final: norznab NO va vía Prowlarr.** Al revisar Radarr/Sonarr se vio que **norznab ya estaba integrado directamente** como 3 indexers (DonTorrent, EliteTorrent, Wolfmax4K → todos `http://norznab.arr.svc.cluster.local:3000`, cada uno con una API key que selecciona su fuente vía `selectBySource`). Meter norznab como Generic Torznab en Prowlarr sería redundante y duplicaría (el genérico usa todas las fuentes a la vez). Se eliminó "norznab (Prowlarr)" de Prowlarr. El fix de `t=search` se mantiene (mejora válida: norznab ahora soporta el estándar Torznab completo).
- **Configuración final de indexers**:
  - **Prowlarr** (sincroniza a Radarr+Sonarr): Milnueve (ES) + Torrentio (internacional).
  - **Directos en Radarr/Sonarr** (norznab por fuente): DonTorrent + EliteTorrent + Wolfmax4K.
  - Radarr y Sonarr quedan con los 5 indexers (3 directos + 2 de Prowlarr), verificado vía API.
