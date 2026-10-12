---
title: "Proxy smart bypass LaLiga para los arr"
status: To Do
priority: 2
labels: [arr, networking, laliga, proxy]
parent:
references:
  - "https://hayahora.futbol/"
  - "https://hayahora.futbol/estado/data.json"
  - "https://github.com/jmalarcon/SiFutbolNoCF"
created_date: 2026-10-12 12:38
---

## Description

## 📌 TLDR

Proxy HTTP(S) forward para los *arr que por defecto deja salir el tráfico directo (máxima velocidad) y, cuando detecta que LaLiga está bloqueando las IPs de Cloudflare relevantes, conmuta el upstream al proxy de gluetun (VPN) para esquivar el bloqueo. Doble disparador: señal de la API de `hayahora.futbol` + circuit breaker por códigos de respuesta HTTP. Recuperación automática al despejarse.

## 🎯 Contexto funcional

Durante los partidos de fútbol, LaLiga fuerza a los ISPs a bloquear **por IP de destino** rangos de Cloudflare para tumbar streams pirata. De rebote cae `api.radarr.video` (metadatos SkyHook/TMDb), alojado en el rango `188.114.96.0/24`, y en Radarr "no cargan las búsquedas" al añadir pelis nuevas. El síntoma es recurrente y se resuelve solo al acabar el fútbol, pero mientras dura deja los *arr parcialmente inoperativos. Ver memoria `laliga-cloudflare-ip-block-radarr-search`.

Meter todo el tráfico de los *arr permanentemente por la VPN no interesa (penaliza velocidad y es innecesario el 95% del tiempo). La idea es un proxy que esté en medio y **solo** desvíe por gluetun cuando de verdad hay bloqueo, volviendo a directo en cuanto pasa.

## ⚙️ Contexto técnico

**Topología:** los *arr apuntan `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` al nuevo proxy (patrón ya usado — está comentado en `lib/arr/norznab/norznab.libsonnet:36`). El proxy decide dinámicamente:
- **cerrado (normal):** passthrough directo, salida por la red del NAS.
- **abierto (bloqueo):** encadena el upstream al HTTP proxy de gluetun en `gluetun.system.svc.cluster.local:8888` (ya desplegado, ProtonVPN, `lib/system/gluetun/gluetun.libsonnet`).

**Disparador A — API de hayahora.futbol:** el NAS sale por **Vodafone**, así que se sondea la lista de Vodafone (`https://hayahora.futbol/estado/blocked-vodafone.txt` — una IP por línea, vacío = sin bloqueos; o `data.json` con `isp:"Vodafone"` y `stateChanges[].state`). Si aparece bloqueado el rango `188.114.96.0/24` (IPs de `api.radarr.video`) → abrir. Sondeo a intervalos razonables (evitar martillear la API; SiFutbolNoCF usa intervalos "inteligentes" según hora/partido). API documentada en memoria `hayahora-futbol-api-endpoints`.

**Disparador B — circuit breaker por status HTTP:** el proxy observa las respuestas (timeouts/5xx/403) y, al superar un umbral configurable en una ventana temporal, abre el circuito aunque la API aún no marque el bloqueo (reacciona antes, y cubre bloqueos no reflejados en hayahora). Half-open: sonda periódica directa; si recupera, cierra.

**Alcance del routing (a decidir en el plan):** objetivo preferido = desviar por gluetun **solo los dominios afectados** (`api.radarr.video` y similares de Cloudflare), no todo el tráfico del *arr, para no cargar la VPN innecesariamente.

**Implementación (a evaluar en el plan):** opción A = proxy existente con scripting (p. ej. mitmproxy + addon en Python, que da acceso a status codes y permite reescribir upstream por request); opción B = pequeño servicio propio. Preferir algo mantenible y observable sobre reinventar un proxy.

**Despliegue:** namespace `arr`, módulo `.libsonnet` nuevo siguiendo el patrón del repo (Deployment + Service + ConfigMap), versión en `versions.json`, `u.labelApp()` para que ArgoCD y Reloader lo recojan.

## Acceptance Criteria

- [ ] #1 Proxy HTTP(S) forward desplegado en `arr`, con los *arr (Radarr/Prowlarr/Sonarr/Lidarr) apuntando su `HTTP_PROXY`/`HTTPS_PROXY` a él.
- [ ] #2 Estado por defecto = passthrough directo (sin VPN).
- [ ] #3 Disparador A: sondeo periódico de la lista de Vodafone de hayahora.futbol; si las IPs de Cloudflare relevantes (`188.114.96.0/24` / `api.radarr.video`) están bloqueadas, conmuta el upstream a gluetun.
- [ ] #4 Disparador B: circuit breaker por códigos HTTP; al superar un umbral configurable de errores en una ventana, abre el circuito y enruta por gluetun aunque la API no lo marque aún.
- [ ] #5 Recuperación automática: con API limpia y/o sondeo half-open con éxito, cierra el circuito y vuelve a directo.
- [ ] #6 Al estar abierto, encadena el upstream al HTTP proxy de gluetun (`gluetun.system.svc.cluster.local:8888`).
- [ ] #7 Observabilidad: estado del circuito (abierto/cerrado, motivo, nº de conmutaciones) consultable en Loki/Grafana.

## Definition of Done

- [ ] #1 desplegar con /deploy

## Implementation Plan

## Implementation Notes
