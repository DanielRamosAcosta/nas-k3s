---
id: NASKS-3
title: Set up declarative DNS management from Kubernetes with external-dns
status: To Do
assignee: []
created_date: '2026-03-09 16:50'
updated_date: '2026-04-10 16:17'
labels:
  - infra
  - feature
  - kubernetes
dependencies: []
references:
  - 'https://github.com/kubernetes-sigs/external-dns'
  - tanka/lib/system/cloudflare.libsonnet
  - hosts/shared/services/dnsmasq.nix
  - hosts/shared/services/cloudflared.nix
  - tanka/environments/versions.json
priority: medium
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Montar gestión declarativa de DNS desde Kubernetes usando external-dns (o similar) para que los registros DNS se creen/actualicen automáticamente a partir de los recursos del clúster (IngressRoutes, Services, etc.), en lugar de gestionarlos manualmente.

## Estado actual

- **Dominio:** `danielramos.me` gestionado en Cloudflare
- **DDNS:** Un CronJob de Cloudflare en el namespace `system` que mantiene `nas.danielramos.me` apuntando a la IP externa
- **dnsmasq local:** Resuelve `photos.danielramos.me` → `192.168.1.200` (IP del NAS) para tráfico interno
- **Cloudflared tunnel:** Túnel SSH a `ssh.danielramos.me`
- **Subdominios actuales:** photos, music, media, cloud, invidious, auth, grafana — todos configurados manualmente en Cloudflare

## Problema

Cada vez que se añade un servicio nuevo hay que crear el registro DNS a mano en Cloudflare y/o en dnsmasq. Con external-dns esto sería automático y declarativo.

## Opciones

### Opción A: external-dns de kubernetes-sigs (recomendada)
https://github.com/kubernetes-sigs/external-dns — Proyecto oficial de Kubernetes SIG. Observa recursos de Ingress/Service y sincroniza registros DNS con el proveedor (Cloudflare soportado nativamente).

- **Pros:** Proyecto maduro y estándar, soporte nativo de Cloudflare, compatible con Traefik IngressRoutes (vía CRD source), amplia comunidad
- **Cons:** Necesita un API token de Cloudflare con permisos de escritura en la zona DNS

### Opción B: Cloudflare Operator
https://github.com/adyanth/cloudflare-operator — Operator de Kubernetes específico para Cloudflare. Gestiona registros DNS y túneles Cloudflare como CRDs.

- **Pros:** Integración más profunda con Cloudflare (túneles + DNS), CRDs nativos
- **Cons:** Proyecto más pequeño, menos mantenido, acoplado a Cloudflare

### Opción C: external-dns + dnsmasq local
Usar external-dns para Cloudflare (registros públicos) y además generar la config de dnsmasq desde los mismos recursos para resolución interna (split DNS).

- **Pros:** Resuelve tanto DNS externo como interno de forma declarativa
- **Cons:** Más complejidad, habría que montar un mecanismo para sincronizar dnsmasq

## Consideraciones

- El CronJob actual de Cloudflare DDNS podría reemplazarse o complementarse con external-dns
- Hay que decidir si se quiere `txt` registry (external-dns marca los registros que gestiona para no borrar los manuales)
- El token de Cloudflare ya existe en los secrets cifrados (`secrets.json.age`) — habría que verificar si tiene permisos de escritura DNS
- Desplegar via Tanka en el namespace `system`
- Añadir la versión a `versions.json`
<!-- SECTION:DESCRIPTION:END -->
