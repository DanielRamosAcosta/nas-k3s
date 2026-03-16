---
id: DRAFT-1
title: Montar SMTP relay interno para centralizar credenciales de correo
status: Draft
assignee: []
created_date: '2026-03-16 20:47'
labels:
  - infrastructure
  - improvement
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Desplegar un servicio SMTP relay ligero (maddy, postfix Alpine, o similar) como `smtp.system.svc.cluster.local:25` que reenvíe a Mailgun. Los demás servicios (Grafana, Gitea, Authelia, Immich, SFTPGo) apuntarían al relay sin necesitar credenciales SMTP cada uno. Cambio de proveedor en un solo sitio.
<!-- SECTION:DESCRIPTION:END -->
