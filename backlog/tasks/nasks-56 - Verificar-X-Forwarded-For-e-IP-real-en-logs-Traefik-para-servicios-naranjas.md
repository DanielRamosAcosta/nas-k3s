---
id: NASKS-56
title: Verificar X-Forwarded-For e IP real en logs Traefik para servicios naranjas
status: To Do
assignee: []
created_date: '2026-04-22 20:36'
labels:
  - infra
  - traefik
  - observability
  - followup-nasks-53
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

En NASKS-53 añadimos `forwardedHeaders.trustedIPs` a Traefik con los CIDRs de Cloudflare (v4 + v6). El objetivo era que para servicios naranjas (proxied vía CF) el `X-Forwarded-For` llegue con la IP real del cliente y Traefik la use como source, en vez del IP del edge de CF. Esto es crítico para:
- Que Crowdsec banee al atacante real, no a CF.
- Que los logs de Traefik muestren IPs útiles.
- Que cualquier rate limit futuro sobre naranjas opere contra IPs reales.

Quedó **sin validar al cierre de NASKS-53**. Es el criterio #13 de esa task.

## Pasos

1. Habilitar access logs en Traefik (hoy no están activos — solo se ven logs de probes de k8s):
   - En `lib/system/traefik/traefik.libsonnet` añadir al bloque `logs`:
     ```jsonnet
     access: {
       enabled: true,
       format: 'json',
     },
     ```
   - Commit + push. ArgoCD sync.

2. Hacer un request controlado desde una IP conocida a un servicio naranja (p.ej. `curl -sI https://auth.danielramos.me` desde tu casa o un VPS).

3. En Loki / Grafana Logs, filtrar:
   ```
   {pod=~"traefik-.*"} | json | ClientAddr != ""
   ```
   Verificar que `ClientAddr` (o `ClientHost`) muestra la IP real del cliente, no un CIDR de CF (104.16.0.0/13, etc.).

4. Como control negativo, hacer un request a `photos.danielramos.me` (gray, sin CF en medio) y confirmar que sigue mostrando la IP real directa.

5. Si NO muestra la IP real, debug:
   - ¿Se aplicó `trustedIPs` bien? Verificar args del container (`kubectl -n system get deploy traefik -o jsonpath='{...args...}'`).
   - ¿CF está mandando los headers? Revisar `CF-Connecting-IP` / `X-Forwarded-For` con `curl -v` desde cliente.
   - ¿Traefik está reescribiendo el source IP en el log? Mirar que `access.log` incluya `ClientAddr` del proxy chain después de los trustedIPs.

## Consideración: formato del access log

JSON estructurado ayuda a parsear con Crowdsec y Loki. Si prefieres line-based (more legible por humanos), usa `format: 'common'`. JSON es más machine-friendly.

## Acceptance criteria

- [ ] Access logs Traefik habilitados (JSON) y fluyen a Loki.
- [ ] Request externo a servicio naranja muestra IP real del cliente (no IP de CF) en el log.
- [ ] Request a photos (gray) sigue mostrando la IP directa del cliente.
- [ ] Documentado en el módulo Traefik cuál es el formato elegido y por qué.

## No scope

- Dashboard Grafana de logs de acceso (otra task si lo quieres).
- Retention / log rotation tuning.
<!-- SECTION:DESCRIPTION:END -->
