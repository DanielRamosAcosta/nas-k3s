---
title: "Migrar todos los client_id de OIDC a identificadores legibles"
status: To Do
priority: 3
labels:
  - authelia
  - oidc
  - refactor
parent:
references:
  - lib/auth/authelia/authelia.config.yml
  - https://www.authelia.com/configuration/identity-providers/openid-connect/clients/
created_date: 2026-10-12 10:24
---

## Description

## 📌 TLDR

Todos los clientes OIDC de Authelia usan un `client_id` aleatorio sellado. El `client_id` **no es un secreto** en OAuth2 (viaja en la URL del navegador en cada login), así que se migran a identificadores legibles y públicos (p. ej. el slug del servicio), dejando de sellarlos. El `client_secret` sigue sellado/hasheado.

## 🎯 Contexto funcional

El `client_id` se trataba como secreto por costumbre (las guías de Authelia recomiendan un aleatorio de ~64 chars). Pero la doc de Authelia exige solo que sea único, ≤100 chars y con caracteres RFC3986 — explícitamente permite "any arbitrary value". Lo aleatorio aporta unicidad y una leve no-adivinabilidad (anti-enumeración), nunca confidencialidad. Publicarlos no abre ningún vector (sin el `client_secret` no se canjea token). La migración simplifica la config (menos entradas selladas, valores legibles en git) y es coherente con dejar los `homeserver.yaml`/configs estáticos.

Clientes OIDC actuales (9): Immich, SFTPGo, Grafana, Jellyfin, Grimmory, ArgoCD, ArgoCD CLI, FacturaScripts, Synapse. **Synapse ya se migró** en la tarea "Refactorizar config de Synapse…" (`client_id: synapse`) y sirve de patrón.

## ⚙️ Contexto técnico

Por cada cliente hay dos lados que deben coincidir exactamente:
1. **Authelia** — `lib/auth/authelia/authelia.config.yml`: cambiar `client_id: '{{ env IDENTITY_PROVIDERS_OIDC_CLIENTS_<APP>_CLIENT_ID }}'` por el valor legible en claro; quitar la entrada sellada correspondiente de `authelia.secrets.json`.
2. **Servicio consumidor** — cada app referencia su `client_id` de forma distinta (env var, config, a veces sellado en su propio `secrets.json`). Hay que localizar dónde y ponerlo en claro con el mismo valor legible.

Convención propuesta: el slug del servicio en minúsculas (`immich`, `sftpgo`, `grafana`, `jellyfin`, `grimmory`, `argocd`, `argocd-cli`, `facturascripts`). Deben ser únicos entre sí (criterio de Authelia).

Cada migración fuerza re-login OIDC de ese servicio (el cambio de `client_id` invalida sesiones en curso). Desplegar Authelia + el servicio juntos.

## Acceptance Criteria

- [ ] #1 Convención de nombres legibles acordada y aplicada de forma única por cliente
- [ ] #2 Cada cliente tiene su `client_id` legible en `authelia.config.yml` (plaintext) y en la config del servicio consumidor, con el `client_secret` intacto y sellado
- [ ] #3 Eliminadas todas las entradas selladas `IDENTITY_PROVIDERS_OIDC_CLIENTS_*_CLIENT_ID` de `authelia.secrets.json` y cualquier `client_id` sellado en los `secrets.json` de cada servicio
- [ ] #4 Verificado el login OIDC de cada servicio tras el despliegue (re-login forzado)
- [ ] #5 `tk eval` de los entornos afectados sin errores

## Implementation Plan

## Implementation Notes
