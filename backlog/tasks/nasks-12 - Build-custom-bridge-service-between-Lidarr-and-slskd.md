---
id: nasks-12
title: Build custom bridge service between Lidarr and slskd
status: To Do
assignee: []
created_date: '2026-03-09 17:05'
updated_date: '2026-03-09 17:12'
labels:
  - media
  - feature
  - kubernetes
dependencies: []
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Desarrollar un servicio custom que actúe de puente entre Lidarr (gestor de música) y slskd (cliente Soulseek). El objetivo es automatizar la descarga de música: cuando Lidarr detecta un álbum o canción que falta, el servicio busca y descarga automáticamente desde la red Soulseek a través de slskd, y notifica a Lidarr cuando la descarga se completa.

## Contexto

- **Lidarr** es un gestor de colección musical (tipo Sonarr/Radarr pero para música). Monitoriza artistas y álbumes, y puede integrar con clientes de descarga.
- **slskd** es un cliente Soulseek self-hosted con API REST, ideal para encontrar música rara o en FLAC que no está en otras fuentes.
- No existe una integración nativa entre ambos — hay que construir el puente.

## Funcionalidad esperada

- Escuchar peticiones de descarga de Lidarr (vía webhook o polling de la API)
- Buscar en slskd las canciones/álbumes solicitados
- Seleccionar el mejor resultado (por calidad, formato, seeds)
- Iniciar la descarga en slskd
- Monitorizar el progreso de la descarga
- Mover/renombrar los archivos descargados al directorio que Lidarr monitoriza
- Notificar a Lidarr para que importe los archivos

## Consideraciones técnicas

- Ambos servicios (Lidarr y slskd) tienen APIs REST documentadas
- Desplegar como contenedor en K3s
- Definir en Tanka como parte del stack de media
- Añadir versión a `versions.json`
<!-- SECTION:DESCRIPTION:END -->
