---
id: NASKS-88
title: >-
  Reactivar VPN gluetun (credenciales ProtonVPN) para salida de Radarr durante
  bloqueos de LaLiga
status: In Progress
assignee: []
created_date: '2026-08-22 20:44'
labels: []
dependencies: []
references:
  - lib/system/gluetun/gluetun.libsonnet
  - lib/system/gluetun/gluetun.secrets.json
  - 'https://wiki.servarr.com/radarr/environment-variables'
priority: medium
type: bug
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

El pod `gluetun` (namespace `system`) está en bucle de `AUTH_FAILED` contra ProtonVPN: las credenciales OpenVPN del SealedSecret están caducadas/incorrectas, el túnel nunca sube y el killswitch bloquea toda la salida. Renovar las credenciales OpenVPN para dejar operativo su proxy HTTP (`:8888`), de modo que Radarr pueda salir por la VPN y esquivar los bloqueos por IP de rangos Cloudflare que impone LaLiga durante el fútbol.

## 🎯 Contexto funcional

Durante los partidos, LaLiga fuerza a los ISPs a bloquear por IP rangos de Cloudflare para tumbar streams pirata. De rebote cae `api.radarr.video` (metadatos SkyHook/TMDb, rango `188.114.96.0/24`), lo que hace que en Radarr "no carguen las búsquedas" al añadir películas. El resto de internet y el indexer local (norznab) funcionan; solo falla la salida directa hacia ese rango bloqueado. Enrutando la salida de Radarr por la VPN (que sale por Países Bajos) se esquiva el bloqueo.

## ⚙️ Contexto técnico

- gluetun: `lib/system/gluetun/gluetun.libsonnet`, deployment en namespace `system`, proxy HTTP en `gluetun.system.svc.cluster.local:8888` (`HTTPPROXY: on`), provider `protonvpn` + `openvpn`, `FREE_ONLY: on`.
- Síntoma en logs: `ERROR [openvpn] AUTH: Received control message: AUTH_FAILED` + `Your credentials might be wrong` + `SIGUSR1[soft,auth-failure] received, process restarting` en bucle (~10s). Llega al servidor (`node-nl-161.protonvpn.net`) → rechazo de auth, no caída de servidor.
- Secreto: SealedSecret `gluetun-sealed-secret` (namespace `system`, scope strict), claves `OPENVPN_USER` y `OPENVPN_PASSWORD`, en `lib/system/gluetun/gluetun.secrets.json`. Renovar con `./scripts/encrypt-secret.sh system gluetun-sealed-secret`.
- Radarr NO admite proxy por env var: el proxy vive en su BD/config.xml y no está entre los namespaces overrideables (`APP/AUTH/LOG/POSTGRES/SERVER/UPDATE`). La config del proxy en Radarr (proxyEnabled + `gluetun.system.svc.cluster.local:8888`, tipo HTTP) la realiza el usuario manualmente en la UI (Settings → General → Proxy) — fuera del alcance de este ticket.
- Despliegue vía GitOps (commit a main → rama manifests → ArgoCD auto-sync). Reloader reinicia gluetun al cambiar el secret.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 gluetun conecta a ProtonVPN sin AUTH_FAILED: túnel OpenVPN establecido y estable (verificado en logs vía Loki)
- [ ] #2 El proxy HTTP de gluetun (:8888) tiene salida a internet verificada — api.radarr.video responde a través del proxy pese al bloqueo por IP
- [ ] #3 Credenciales OpenVPN nuevas selladas en gluetun.secrets.json (strict, system/gluetun-sealed-secret) y desplegadas por GitOps
- [ ] #4 Verificación final: con el proxy configurado en la UI de Radarr, las búsquedas de películas funcionan durante un bloqueo de LaLiga
<!-- AC:END -->
