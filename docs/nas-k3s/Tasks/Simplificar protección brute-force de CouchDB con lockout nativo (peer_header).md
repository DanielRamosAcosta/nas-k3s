---
title: "Simplificar protección brute-force de CouchDB con lockout nativo (peer_header)"
status: Blocked
priority: 3
labels:
  - databases
  - tech-debt
  - security
parent:
dependencies:
  - "[[Proteger CouchDB contra brute-force de auth con Crowdsec en Traefik]]"
references:
  - 'https://github.com/apache/couchdb/issues/6052'
  - 'https://github.com/apache/couchdb/pull/6063'
  - 'https://docs.couchdb.org/en/stable/config/http.html'
  - lib/databases/couchdb/couchdb.libsonnet
  - lib/system/crowdsec/crowdsec.libsonnet
created_date: 2026-10-12 09:36
---

## Description

## 📌 TLDR

Cuando salga **CouchDB 3.6.0** (incluye el setting `[chttpd] peer_header` del PR #6063, fix del issue #6052), activar el lockout de auth nativo con la **IP real** del cliente tras Cloudflare/Traefik y **retirar el workaround de Crowdsec específico de CouchDB** (scenario `couchdb-http-auth-bf` + Middleware bouncer). Simplifica la defensa montada en [[Proteger CouchDB contra brute-force de auth con Crowdsec en Traefik]].

## 🎯 Contexto funcional

CouchDB está expuesto (`couchdb.danielramos.me`) con basic auth nativo. Hoy la protección brute-force la da Crowdsec sobre los logs de Traefik (que ve la IP real), porque el lockout nativo de CouchDB (`[chttpd_auth_lockout]`, desde 3.4) tomaba la IP del **último** `X-Forwarded-For` = el edge de Cloudflare, no el cliente. El PR #6063 (issue #6052) añade `peer_header` para que el lockout use un header de confianza con la IP real → por fin el camino nativo sería viable y podríamos quitar la pieza de Crowdsec, dejando una defensa más simple y con menos superficie de mantenimiento.

## ⚙️ Contexto técnico

**BLOQUEADA**: el fix **no está en ninguna release instalable**. Verificado con `gh` por contenido (no por SHA de merge):

| Ref | `peer_header` en `default.ini` |
|-----|:---:|
| `main` | ✅ |
| `3.5.3` (último release) | ❌ |
| `3.5.x` (rama de mantenimiento) | ❌ (no backporteado) |
| `3.5.2` (la desplegada) | ❌ |

Es un *enhancement* dirigido al próximo minor (**3.6.0**, milestone abierto **sin `due_on`**, sin RC ni tag → **sin fecha**). La línea 3.5.x solo recibe bugfixes. Hasta que no se publique 3.6.0, no hay nada que hacer.

Trabajo cuando se desbloquee:
1. Subir CouchDB a ≥3.6.0 (`lib/versions.json`, hoy `3.5.2`).
2. En `couchdb.config.ini` fijar `[chttpd] peer_header = CF-Connecting-IP` (header que Cloudflare/Traefik ponen con la IP real). **Seguridad (nota de nickva en el PR):** el reverse proxy debe **fijar/limpiar** ese header para que el cliente no pueda spoofearlo; confirmar que Traefik/Cloudflare lo garantizan antes de confiar en él.
3. Confirmar que el lockout nativo (`[chttpd_auth_lockout]`, ya activo por defecto) cuenta los `401` por IP real.
4. Retirar el workaround de Crowdsec específico de CouchDB: el scenario `couchdb-http-auth-bf.yaml` en `lib/system/crowdsec/crowdsec.libsonnet` y el Middleware `couchdb-crowdsec-bouncer` + su referencia en el `ingress_route` de `lib/databases/couchdb/couchdb.libsonnet`.

## Acceptance Criteria

- [ ] #1 CouchDB desplegado en ≥3.6.0 y `[chttpd] peer_header` configurado con el header que porta la IP real del cliente tras Cloudflare/Traefik
- [ ] #2 Confirmado que el reverse proxy fija/limpia ese header (el cliente no puede spoofearlo)
- [ ] #3 El lockout nativo banea tras N `401` desde la misma IP real (verificado end-to-end, sobre la IP pública real y no el edge de Cloudflare)
- [ ] #4 Retirado el workaround de Crowdsec de CouchDB: scenario `couchdb-http-auth-bf` + Middleware `couchdb-crowdsec-bouncer` y su referencia en el IngressRoute
- [ ] #5 El sync de Obsidian LiveSync no se ve afectado (ráfagas `200/201` no disparan el lockout)

## Implementation Plan

## Implementation Notes
