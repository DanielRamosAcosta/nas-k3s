---
id: NASKS-75
title: Proteger CouchDB contra brute-force de auth con Crowdsec en Traefik
status: In Progress
assignee:
  - Daniel
created_date: '2026-06-26 19:46'
updated_date: '2026-06-26 20:30'
labels: []
dependencies: []
references:
  - 'https://github.com/apache/couchdb/issues/6052'
  - lib/media/immich/immich.libsonnet
  - lib/system/crowdsec/crowdsec.libsonnet
  - lib/system/traefik/traefik.libsonnet
  - lib/databases/couchdb/couchdb.libsonnet
priority: high
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

CouchDB está expuesto a internet (`couchdb.danielramos.me`) con solo basic auth nativo y sin rate limit efectivo. Aplicar el bouncer de Crowdsec al IngressRoute de CouchDB y añadir un scenario que detecte brute-force de auth (varios `401` desde la misma IP) para banear al atacante por su IP real, sin afectar al sync legítimo de Obsidian LiveSync.

## 🎯 Contexto funcional

CouchDB sirve el sync de Obsidian (`obsidian-vault`) y está expuesto vía Cloudflare (orange-proxy) sin Authelia ni middlewares — la autenticación la lleva el basic auth nativo de CouchDB. Meter Authelia/forward-auth delante rompería Obsidian LiveSync (el plugin manda basic auth, no navega un flujo OIDC), por eso el diseño actual lo deja sin middleware.

El único muro hoy es la fortaleza de las contraseñas (`admin` y `obsidian`): cualquiera puede martillar el basic auth sin límite de intentos. El rate limit nativo de CouchDB (lockout de `[chttpd_auth_lockout]`, desde 3.4) es **inservible detrás de Cloudflare**: mochiweb (`get(peer)`, v3.4.0) toma el **último** valor de `X-Forwarded-For` (`lists:last`), que en la cadena con CDN es siempre el edge de Cloudflare y no el cliente real — y no es configurable (investigado y confirmado en código + captura de tráfico en esta sesión; issue de mejora abierto en apache/couchdb#6052).

La defensa debe ir en Traefik, que sí ve la IP real (capturado: `ClientHost` real vía `forwardedHeaders.trustedIPs` + `CF-Connecting-IP`). Crowdsec es mejor encaje que un rateLimit global porque distingue "fallo de auth" (`401`) de "tráfico intenso legítimo": Obsidian LiveSync genera ráfagas de ~20 req/s con `200/201` que un rateLimit tosco rompería, mientras que un scenario que solo cuenta `401` no las toca.

## ⚙️ Contexto técnico

Infraestructura ya disponible (reutilizar, no crear de cero):
- **Crowdsec ya desplegado** (`lib/system/crowdsec/crowdsec.libsonnet`): LAPI in-cluster, decisiones en Postgres, bouncer key pre-registrada (`crowdsec-bouncer-key`).
- **Adquisición de logs de Traefik ya configurada**: el agente lee los logs de Traefik vía Loki (`{namespace="system",pod=~"traefik-.*"}`, `labels.type: traefik`) → opera sobre la **IP real** (la que Traefik resuelve con `forwardedHeaders.trustedIPs` + `externalTrafficPolicy: Local`), NO la del edge de Cloudflare.
- **Detección de brute-force ya instalada**: `COLLECTIONS` incluye `crowdsecurity/traefik` + `crowdsecurity/base-http-scenarios`, y esta última **ya trae `crowdsecurity/http-generic-bf`** (brute-force de HTTP basic auth: cuenta `401`, capacidad 5, leakspeed 10s). El detector de 401-bruteforce ya corre sobre los logs de Traefik.
- **Plugin bouncer ya cargado en Traefik** (`maxlerebourg/crowdsec-bouncer-traefik-plugin`) — ver `lib/system/traefik/traefik.libsonnet`.
- **Patrón de referencia ya montado en immich** (`lib/media/immich/immich.libsonnet`): Middleware `crowdsecBouncer` (plugin bouncer, `crowdsecMode: stream`, `crowdsecLapiKeyFile`, **`forwardedHeadersTrustedIPs: cloudflare.allCidrs`**), aplicado vía `u.ingressRoute.from(service, host, middlewares, extraRoutes)`.

**Descartado — colección `aidalinfo/couchdb`**: existe una colección de Crowdsec específica de CouchDB (parser + scenarios crawl/bruteforce), pero **NO sirve aquí**: parsea los **logs de CouchDB**, donde la IP es la del edge de Cloudflare (mismo problema del `lists:last` que el lockout nativo) → Crowdsec banearía a Cloudflare, no al atacante. La detección debe ir sobre los logs de **Traefik** (IP real), no los de CouchDB.

Trabajo a realizar (alto nivel) — el grueso es enganchar el bouncer y afinar la detección, no construirla:
1. Aplicar un Middleware bouncer de Crowdsec al IngressRoute de CouchDB en `lib/databases/couchdb/couchdb.libsonnet` (patrón immich; decidir si se comparte un bouncer común o uno por servicio).
2. Verificar/ajustar la detección: `http-generic-bf` filtra por `verb == 'POST' && status 401`, pero CouchDB manda basic auth en **cualquier** verbo (un brute-force por `GET /` daría `401` sin ser POST). Comprobar si lo captura tal cual o si hace falta un scenario propio que cuente `401` de cualquier verbo contra el host de CouchDB. Decidir umbral/ventana.
3. Verificar end-to-end: ráfaga de `401` → ban (`403` del bouncer), y que el sync de Obsidian (`200/201`) no se vea afectado.

Nota: el lockout nativo de CouchDB puede quedarse activo como defensa en profundidad, pero no se cuenta como protección efectiva.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Un Middleware de Traefik aplica el bouncer de Crowdsec al IngressRoute de couchdb.danielramos.me, reutilizando el patrón de immich con forwardedHeadersTrustedIPs: cloudflare.allCidrs para operar sobre la IP real (no el edge de Cloudflare)
- [ ] #2 La detección de brute-force de auth contra CouchDB opera sobre los logs de Traefik (IP real), apoyándose en crowdsecurity/http-generic-bf ya instalado y cubriendo 401 de cualquier verbo contra el host de CouchDB → genera una decisión de ban
- [ ] #3 El sync legítimo de Obsidian LiveSync no se ve afectado: las ráfagas de 200/201 no disparan ban ni bloqueo (el scenario solo cuenta 401)
- [ ] #4 Una IP que supera el umbral de 401 recibe 403 del bouncer, verificado end-to-end
- [ ] #5 El ban se aplica sobre la IP real del cliente, confirmado en la práctica
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Ejecución secuencial fase a fase: implementar una fase, desplegar, verificar su checkpoint, y solo entonces pasar a la siguiente. Despliegue = GitOps (`/deploy`: commit+push a main → CI exporta a la rama `manifests` → ArgoCD sincroniza). Reloader reinicia los pods afectados al cambiar ConfigMaps/Secrets.

**Decisión de diseño:** se crea un Middleware bouncer propio para CouchDB en el namespace `databases` (mismo patrón que immich, que tiene el suyo en `media`), en vez de compartir uno cross-namespace. Refactor a un bouncer compartido = fuera de scope.

### Fase 1 — Enganchar el bouncer de Crowdsec al IngressRoute de CouchDB

Riesgo bajo: el bouncer solo bloquea IPs con una decisión activa en el LAPI; sin scenarios nuevos todavía no hay decisiones, así que no debe bloquear nada. Valida el wiring de forma segura.

1. En `lib/databases/couchdb/couchdb.libsonnet`, añadir el import `local cloudflare = import '../../utils/cloudflare.libsonnet';` (estilo relativo, consistente con el `import '../../utils.libsonnet'` que ya usa el fichero y con immich) y definir un recurso `crowdsecBouncer` copiando el Middleware de immich (`lib/media/immich/immich.libsonnet:96-119`), con `metadata.name: 'couchdb-crowdsec-bouncer'` y `spec.plugin.bouncer` { `enabled: true`, `logLevel: 'INFO'`, `crowdsecMode: 'stream'`, `updateIntervalSeconds: 60`, `crowdsecLapiScheme: 'http'`, `crowdsecLapiHost: 'crowdsec-service.system.svc.cluster.local:8080'`, `crowdsecLapiKeyFile: '/etc/crowdsec-bouncer/BOUNCER_KEY'`, `forwardedHeadersTrustedIPs: cloudflare.allCidrs` }.
2. Cambiar `ingress_route: u.ingressRoute.from(self.service, 'couchdb.danielramos.me')` por `u.ingressRoute.from(self.service, 'couchdb.danielramos.me', [{ name: self.crowdsecBouncer.metadata.name }])`.
3. Validar render local: `tk eval environments/databases | jq '.. | select(.kind? == "Middleware" and .metadata.name == "couchdb-crowdsec-bouncer")'` y comprobar que el IngressRoute de couchdb lleva el middleware en su ruta. Confirmar que el Middleware hereda el label `app` de couchdb (vía `u.labelApp` en `environments/databases/main.jsonnet`) para que ArgoCD lo gestione bajo la Application de couchdb.
4. **Desplegar** con la skill `/deploy`.
5. Checkpoint:
   - `kubectl get middleware couchdb-crowdsec-bouncer -n databases` existe; el IngressRoute lo referencia.
   - El sync de Obsidian sigue OK: en Loki `{namespace="system",pod=~"traefik.*"} | json | RequestHost="couchdb.danielramos.me"` sigue dando `200/201`, sin `403` espurios.
   - Logs del bouncer sin errores de conexión al LAPI: `{namespace="system",pod=~"traefik.*"} |= "bouncer"` en Loki.

### Fase 2 — Detección: scenario de 401 brute-force para CouchDB

Objetivo: que Crowdsec genere una decisión de ban ante `401` repetidos contra el host de CouchDB, sobre la IP real (logs de Traefik, ya adquiridos vía Loki).

1. Recopilar evidencia del verbo: provocar ~10 `401` con `curl -s -o /dev/null -w "%{http_code} " https://couchdb.danielramos.me/` (GET sin credenciales) y revisar en Loki `{namespace="system",pod=~"traefik.*"} | json | RequestHost="couchdb.danielramos.me" | DownstreamStatus="401"` → anotar `RequestMethod` (se espera `GET`, no `POST`).
2. Confirmar que `crowdsecurity/http-generic-bf` (filtra `verb == 'POST'`) NO captura esos `401` de verbo `GET` → por eso hace falta un scenario propio.
3. Confirmar el nombre exacto del campo de host/verbo/status/source_ip que expone el parser `crowdsecurity/traefik`: `kubectl exec -n system ds/crowdsec-agent -- cscli explain --log '<línea JSON de traefik real>' --type traefik` (o `--dsn`), y anotar los campos `evt.Meta.*` / `evt.Parsed.*` resultantes.
4. En `lib/system/crowdsec/crowdsec.libsonnet`, añadir bajo `values.config` el bloque `scenarios: { 'couchdb-http-auth-bf.yaml': '<yaml>' }`. Scenario tipo `leaky` que: filtre por `log_type` de access-log + `http_status == '401'` + host == `couchdb.danielramos.me` (usando el campo confirmado en el paso 3); `groupby` por la IP de origen; `capacity`/`leakspeed` tolerantes con la ráfaga legítima (que es `200/201`, no `401` — p. ej. `capacity: 10`, `leakspeed: 5s`); `blackhole`; `labels.remediation: true`. Nota: el módulo NO define `profiles.yaml` a propósito, así que el ban depende del `profiles.yaml` por defecto de la imagen (`Alert.Remediation == true && scope == Ip` → ban) — por eso `labels.remediation: true` es el lever que dispara la decisión.
5. Validar render local: `tk eval environments/system | jq '.. | select(.kind? == "ConfigMap" and .metadata.name == "crowdsec-scenarios")'` y comprobar que el scenario `couchdb-http-auth-bf.yaml` aparece en ese ConfigMap.
6. **Desplegar** con la skill `/deploy`. (Reloader reinicia el agente de crowdsec al cambiar su ConfigMap.)
7. Checkpoint:
   - `kubectl exec -n system ds/crowdsec-agent -- cscli scenarios list | grep couchdb` muestra el scenario cargado.
   - El agente arrancó sin error de parseo: `{namespace="system",pod=~"crowdsec.*"}` en Loki sin errores de scenario.

### Fase 3 — Verificación end-to-end (ban + no-afectación del sync)

Sin cambios de código salvo limpieza de la decisión de prueba. Cubre AC #2/#3/#4/#5.

1. Desde una IP de prueba (distinta a la del cliente de Obsidian) lanzar por encima del umbral: `for i in (seq 1 15); curl -s -o /dev/null -w "%{http_code} " https://couchdb.danielramos.me/; end`.
2. Confirmar la decisión: `kubectl exec -n system deploy/crowdsec-lapi -- cscli decisions list` → aparece un ban para la IP real de prueba.
3. Confirmar AC #5 (IP real): la decisión es para la IP pública real, no un edge de Cloudflare (`162.158.x` / `172.68.x`) ni una IP de clúster (`10.x`).
4. Confirmar AC #4 (ban efectivo): esperar hasta ~60s (modo `stream`, `updateIntervalSeconds: 60`, el bouncer refresca las decisiones del LAPI en cada ciclo) y comprobar que la siguiente request desde esa IP recibe `403` del bouncer, no `401`. Un `401` inmediato no es fallo: es el lag de propagación.
5. Confirmar AC #3 (no-afectación): el sync de Obsidian (otra IP) sigue dando `200/201` y no tiene decisión asociada.
6. Limpiar la decisión de prueba: `kubectl exec -n system deploy/crowdsec-lapi -- cscli decisions delete --ip <ip-de-prueba>`.
7. Checkpoint: AC #2/#3/#4/#5 verificados (AC #1 ya cubierto en Fase 1).
<!-- SECTION:PLAN:END -->
