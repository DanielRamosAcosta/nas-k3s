---
id: NASKS-50
title: Sacar Immich de Cloudflare para esquivar el límite de subida de 100MB
status: To Do
assignee: []
created_date: '2026-04-12 01:46'
labels:
  - networking
  - immich
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Actualmente Immich pasa por el proxy de Cloudflare, que impone un límite de 100MB por request en el plan gratuito. Esto impide subir fotos/vídeos grandes.

La solución es exponer Immich directamente sin pasar por Cloudflare (DNS-only en vez de proxied), o usar un subdominio alternativo que no pase por el proxy. Hay que evaluar las implicaciones de seguridad (se expone la IP del servidor) y considerar alternativas como Cloudflare Tunnel con bypass de límite o split del tráfico.
<!-- SECTION:DESCRIPTION:END -->
