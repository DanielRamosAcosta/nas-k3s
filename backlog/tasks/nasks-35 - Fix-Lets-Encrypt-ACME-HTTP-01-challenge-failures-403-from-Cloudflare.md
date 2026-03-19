---
id: NASKS-35
title: Fix Let's Encrypt ACME HTTP-01 challenge failures (403 from Cloudflare)
status: In Progress
assignee: []
created_date: '2026-03-19 17:02'
updated_date: '2026-03-19 20:06'
labels:
  - traefik
  - cloudflare
  - tls
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Todos los dominios `*.danielramos.me` están fallando la validación ACME HTTP-01 de Let's Encrypt. La secondary validation de LE recibe 403 desde IPs IPv6 de Cloudflare.

**Dominios afectados**: argocd, auth, books, cloud, git, grafana, media, music

**Error**: `invalid authorization: acme: error: 403 :: urn:ietf:params:acme:error:unauthorized :: During secondary validation`

**Restricción**: DNS Only no es opción — el proxy de Cloudflare debe permanecer activo.

**Opciones a evaluar**:
- Cambiar a DNS-01 challenge con Cloudflare API token en Traefik
- Crear regla en Cloudflare WAF para permitir requests a `/.well-known/acme-challenge/*`
- Usar Cloudflare Origin Certificates en lugar de Let's Encrypt (solo válidos con proxy activo)
<!-- SECTION:DESCRIPTION:END -->
