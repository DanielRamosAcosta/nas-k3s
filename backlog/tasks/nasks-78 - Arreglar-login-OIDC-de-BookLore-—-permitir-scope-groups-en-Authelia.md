---
id: NASKS-78
title: Arreglar login OIDC de BookLore — permitir scope 'groups' en Authelia
status: In Progress
assignee: []
created_date: '2026-06-28 19:57'
labels: []
dependencies: []
references:
  - lib/auth/authelia/authelia.config.yml
  - lib/media/booklore/booklore.libsonnet
  - lib/media/booklore/booklore.logback-spring.xml
priority: medium
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

El login OIDC de BookLore falla con `invalid_scope` porque BookLore solicita el scope `groups` pero el cliente `Booklore` en Authelia no lo permite. Hay que añadir `groups` a los scopes del cliente y al claims_policy `booklore`.

## 🎯 Contexto funcional

Al intentar autenticarse en `https://books.danielramos.me`, el navegador muestra:

> `[OIDC Callback] Provider returned error: invalid_scope — The OAuth 2.0 Client is not allowed to request scope 'groups'.`

Tras el fallo, la sesión queda sin autenticar y las llamadas a la API devuelven `403` (p. ej. `GET /api/v1/libraries/health`). BookLore pide `groups` para mapear roles/admin por grupos de Authelia, así que la opción correcta es habilitar ese scope en el IdP en lugar de quitarlo en BookLore.

## ⚙️ Contexto técnico

Diagnóstico realizado vía Loki:
- BookLore (Spring) silencia `org.springframework.security` a WARN en `lib/media/booklore/booklore.logback-spring.xml`, por eso no se veían errores OIDC en los logs.
- Authelia no registraba actividad de booklore → el flujo se rompía en la fase de autorización por el scope rechazado.

El cliente OIDC de BookLore se configura en su UI de admin (BD), no en el repo; el `configEnv` de `booklore.libsonnet` no tiene variables OIDC.

Cambios en `lib/auth/authelia/authelia.config.yml`:
1. Cliente `Booklore` (`client_name: Booklore`): añadir `groups` a la lista `scopes` (junto a `openid`, `offline_access`, `profile`, `email`).
2. `claims_policies.booklore`: añadir `groups` a `id_token` (junto a `email`, `email_verified`, `preferred_username`, `name`).

`groups` es un scope estándar de Authelia, basta con listarlo en el cliente. Reloader reiniciará Authelia al cambiar el ConfigMap; verificar el login tras el deploy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 El cliente Booklore en Authelia incluye 'groups' en su lista de scopes
- [ ] #2 El claims_policy 'booklore' incluye 'groups' en el id_token
- [ ] #3 El login OIDC en books.danielramos.me completa sin error invalid_scope y la sesión queda autenticada (sin el 403 en /api/v1/libraries/health)
<!-- AC:END -->
