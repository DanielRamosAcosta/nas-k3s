---
id: nasks-2
title: Build custom bento-style dashboard with links to all apps
status: To Do
assignee: []
created_date: '2026-03-09 16:48'
updated_date: '2026-03-09 17:12'
labels:
  - dashboard
  - feature
  - kubernetes
dependencies: []
priority: medium
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Construir un dashboard personalizado con layout bento-grid que sirva como página de inicio con enlaces a todas las aplicaciones self-hosted. El objetivo es tener una app hecha por uno mismo (no una solución prefabricada como Homer o Dashy) usando un framework frontend moderno.

## Requisitos

- Layout tipo bento-grid con tarjetas/tiles enlazando a cada servicio
- Construido a medida usando React (o similar: Next.js, Solid, Svelte — preferencia por React)
- Visualmente limpio, responsive
- Fácil de añadir/eliminar/reordenar tiles
- Desplegar como contenedor en el clúster K3s

## Servicios a enlazar (apps actuales)

- Grafana (monitorización)
- Immich (fotos)
- SFTPGo (gestión de archivos)
- Gitea (git)
- Authelia (portal de autenticación)
- Navidrome (música)
- Kubernetes Dashboard
- Cualquier servicio futuro

## Opciones tecnológicas

### Opción A: React + Vite (recomendada)
SPA de React simple empaquetada con Vite. Simple, rápida, no necesita servidor — solo archivos estáticos servidos por nginx o caddy en un contenedor.

- **Pros:** Complejidad mínima, builds rápidos, imagen Docker fácil (nginx + estáticos), control total
- **Contras:** Sin SSR (no necesario para un dashboard), cambios de config requieren rebuild salvo que se externalice

### Opción B: Next.js
Basado en React con capacidades SSR/SSG. Podría leer la config de tiles desde un archivo o API en build time.

- **Pros:** Routing basado en archivos, SSG para export estático, gran ecosistema
- **Contras:** Más pesado de lo necesario para un dashboard de una página, runtime de Node.js en el contenedor

### Opción C: Astro
Generador de sitios estáticos con arquitectura de islas. Puede usar componentes React donde se necesite.

- **Pros:** Output extremadamente rápido, JS mínimo enviado al cliente, puede mezclar frameworks
- **Contras:** Menos familiar si quieres React puro, modelo mental ligeramente diferente

## Ideas de implementación

- Config de tiles como archivo JSON/TS (nombre del servicio, URL, icono, color, tamaño en grid)
- CSS Grid para el layout bento (los tiles pueden ocupar varias filas/columnas)
- Opcional: ping de health check para mostrar estado del servicio (punto verde/rojo)
- Opcional: toggle de tema oscuro/claro
- Containerizar con Dockerfile multi-stage (build con node → servir con nginx)
- Desplegar vía Tanka en un namespace nuevo `dashboard` o `homepage`
- Exponer vía Traefik IngressRoute (ej: home.danielramos.me)
<!-- SECTION:DESCRIPTION:END -->
