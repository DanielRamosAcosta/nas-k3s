---
id: nasks-8
title: Disable WebDAV in SFTPGo
status: To Do
assignee: []
created_date: '2026-03-09 16:54'
updated_date: '2026-03-09 17:12'
labels:
  - security
  - chore
  - kubernetes
dependencies: []
priority: low
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deshabilitar completamente WebDAV en SFTPGo, ya que al final se está usando Samba sobre la VPN para acceso a archivos. Eliminar la configuración de WebDAV, puertos y cualquier IngressRoute asociada para reducir superficie de ataque y simplificar el setup.
<!-- SECTION:DESCRIPTION:END -->
