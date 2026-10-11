---
title: Sacar Immich de Cloudflare para esquivar el límite de subida de 100MB
status: Done
created_date: '2026-04-12 01:46'
labels:
  - networking
  - immich
dependencies: []
priority: 2
ordinal: 8000
---

## Description

Actualmente Immich pasa por el proxy de Cloudflare, que impone un límite de 100MB por request en el plan gratuito. Esto impide subir fotos/vídeos grandes.

La solución es exponer Immich directamente sin pasar por Cloudflare (DNS-only en vez de proxied), o usar un subdominio alternativo que no pase por el proxy. Hay que evaluar las implicaciones de seguridad (se expone la IP del servidor) y considerar alternativas como Cloudflare Tunnel con bypass de límite o split del tráfico.

## Final Summary

Cerrada. El trabajo real se hizo en **[[Migrate photos.danielramos.me to Cloudflare gray cloud with Let's Encrypt DNS-01]]** (migración a Cloudflare gray cloud + Let's Encrypt wildcard DNS-01) y **[[Hardening photos.danielramos.me Crowdsec + geo-block ES CU]]** (Crowdsec full stack + GeoBlock ES/CU). Ambas Done. Esta task era el ticket original del 12-abr planteando el problema a alto nivel; se dejó obsoleta al refinarse el scope en el /grill-me que dio lugar a [[Migrate photos.danielramos.me to Cloudflare gray cloud with Let's Encrypt DNS-01]]+[[Hardening photos.danielramos.me Crowdsec + geo-block ES CU]].

Ver en su lugar:
- [[Migrate photos.danielramos.me to Cloudflare gray cloud with Let's Encrypt DNS-01]] — Migrate photos.danielramos.me to Cloudflare gray cloud with Let's Encrypt DNS-01
- [[Hardening photos.danielramos.me Crowdsec + geo-block ES CU]] — Hardening photos.danielramos.me: Crowdsec + geo-block ES/CU
