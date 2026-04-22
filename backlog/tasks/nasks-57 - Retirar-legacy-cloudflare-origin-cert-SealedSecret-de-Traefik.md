---
id: NASKS-57
title: Retirar legacy cloudflare-origin-cert SealedSecret de Traefik
status: To Do
assignee: []
created_date: '2026-04-22 20:37'
labels:
  - cleanup
  - traefik
  - tls
  - followup-nasks-52
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

En NASKS-52 migramos el TLSStore default de Traefik desde `defaultCertificate` (Cloudflare Origin wildcard cert) a `defaultGeneratedCert` pointed al resolver letsencrypt. El cert viejo (SealedSecret `cloudflare-origin-cert` + el campo `cloudflareOriginCert` en `traefik.secrets.json`) se dejó en el repo bajo un nombre "legacy" como ruta de rollback rápido por si LE daba problemas.

Lleva ya operativo el LE wildcard sin incidencias. Si pasan ~2-4 semanas de estabilidad, podemos retirar el vestigio para limpiar.

## Pasos

1. Verificar en el cluster que ninguna resource referencia la Secret `cloudflare-origin-cert`:
   ```bash
   kubectl get tlsstore,ingressroute,middleware -A -o yaml | grep -i cloudflare-origin-cert
   ```
   Debería salir vacío.

2. En `lib/system/traefik/traefik.libsonnet`, eliminar:
   - `legacyCloudflareOriginSealedSecret: u.sealedSecret.forTls(...)` del bloque final.

3. En `lib/system/traefik/traefik.secrets.json`, eliminar el campo `cloudflareOriginCert`.

4. Commit + push. ArgoCD prune → Secret desaparece del cluster.

5. Sanity check: todos los IngressRoutes siguen sirviendo el LE wildcard (curl a varios hostnames, cert issuer Let's Encrypt).

## Acceptance criteria

- [ ] No hay referencias a `cloudflare-origin-cert` en `lib/`.
- [ ] El SealedSecret `cloudflare-origin-cert` y su Secret asociado ya no existen en el cluster (confirmado con `kubectl get`).
- [ ] Todos los servicios siguen con cert LE válido (smoke test curl).

## No scope

- Revocar el cert Origin en el dashboard de Cloudflare (se puede hacer cuando quieras, pero no es urgente; no afecta nada una vez retirado el mount).
- Retirar el token `CF_DNS_API_TOKEN` (sigue siendo necesario para la renovación DNS-01 del wildcard LE).
<!-- SECTION:DESCRIPTION:END -->
