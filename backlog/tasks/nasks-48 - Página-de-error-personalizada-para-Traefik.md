---
id: NASKS-48
title: Página de error personalizada para Traefik
status: To Do
assignee: []
created_date: '2026-04-05 10:07'
updated_date: '2026-04-10 16:17'
labels:
  - traefik
  - ux
dependencies: []
priority: low
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cuando un servicio backend está caído, Traefik muestra un mensaje genérico "no available server". Queremos reemplazarlo con una página de error bonita y personalizada.

### Enfoque propuesto
1. Desplegar un servicio ligero que sirva páginas de error estáticas (nginx custom o `tarampampam/error-pages`)
2. Crear un Middleware CRD de tipo `errors` que redirija códigos 5xx al servicio de error
3. Aplicarlo globalmente en el entrypoint `websecure` vía Helm values de Traefik, para que aplique a todas las rutas sin modificar cada IngressRoute

### Notas
- El helper `u.ingressRoute.from()` ya soporta middlewares como tercer parámetro, por si se quiere aplicar por ruta en vez de globalmente
- Evaluar si usar página propia o un contenedor preconfigurado como `tarampampam/error-pages`
<!-- SECTION:DESCRIPTION:END -->
