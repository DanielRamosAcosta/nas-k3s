---
title: Retirar legacy cloudflare-origin-cert SealedSecret de Traefik
status: In Progress
created_date: '2026-04-22 20:37'
labels:
  - cleanup
  - traefik
  - tls
  - followup-nasks-52
dependencies: []
priority: 3
ordinal: 60000
---

## Description

## Context

En [[Migrate photos.danielramos.me to Cloudflare gray cloud with Let's Encrypt DNS-01]] migramos el TLSStore default de Traefik desde `defaultCertificate` (Cloudflare Origin wildcard cert) a `defaultGeneratedCert` pointed al resolver letsencrypt. El cert viejo (SealedSecret `cloudflare-origin-cert` + el campo `cloudflareOriginCert` en `traefik.secrets.json`) se dejó en el repo bajo un nombre "legacy" como ruta de rollback rápido por si LE daba problemas.

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

- [x] No hay referencias a `cloudflare-origin-cert` en `lib/`.
- [ ] El SealedSecret `cloudflare-origin-cert` y su Secret asociado ya no existen en el cluster (confirmado con `kubectl get`).
- [x] Todos los servicios siguen con cert LE válido (smoke test curl).

## Implementation Notes

Verificación previa (2026-10-12, ~6 meses tras la migración de abril):

- `kubectl get tlsstore,ingressroute,middleware -A` → **ninguna** resource referencia `cloudflare-origin-cert`. El `Secret`/`SealedSecret` seguían en el cluster (206 días) pero colgados, sin uso.
- Traefik: **cero** errores/warnings de TLS/cert/ACME en Loki en las 2 semanas previas (430 líneas, todo `info`, TLS 1.3, 200/204).
- Smoke test del cert servido directamente por Traefik (gray-cloud `photos.danielramos.me`, sin pasar por el edge de CF): `issuer=Let's Encrypt (YR1)`, `subject=CN=danielramos.me` (wildcard), válido hasta 2026-11-18 → renovación DNS-01 operativa.

Cambios aplicados:

- `lib/system/traefik/traefik.libsonnet`: eliminado el bloque `legacyCloudflareOriginSealedSecret` (+ su comentario de rollback). Actualizado el comentario del resolver ACME, que seguía describiendo el TLSStore default como el Origin cert (obsoleto desde abril).
- `lib/system/traefik/traefik.secrets.json`: eliminado el campo `cloudflareOriginCert` (vía `jq del`, sin leer el valor).
- `lib/databases/couchdb/couchdb.libsonnet`: actualizado el comentario que nombraba `cloudflare-origin-cert` como TLSStore default → wildcard LE.

`tk eval` de `system` y `databases` compila OK; `grep -rni cloudflare-origin-cert lib/` vacío.

Pendiente tras `/deploy`: confirmar que ArgoCD hace prune del `SealedSecret`/`Secret` en el cluster (AC #2).

## No scope

- Revocar el cert Origin en el dashboard de Cloudflare (se puede hacer cuando quieras, pero no es urgente; no afecta nada una vez retirado el mount).
- Retirar el token `CF_DNS_API_TOKEN` (sigue siendo necesario para la renovación DNS-01 del wildcard LE).
