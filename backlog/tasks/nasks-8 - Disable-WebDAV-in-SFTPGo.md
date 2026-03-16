---
id: NASKS-8
title: Disable WebDAV in SFTPGo
status: Done
assignee: []
created_date: '2026-03-09 16:54'
updated_date: '2026-03-16 11:07'
labels:
  - security
  - chore
  - kubernetes
dependencies: []
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deshabilitar completamente WebDAV en SFTPGo, ya que al final se está usando Samba sobre la VPN para acceso a archivos. Eliminar la configuración de WebDAV, puertos y cualquier IngressRoute asociada para reducir superficie de ataque y simplificar el setup.
<!-- SECTION:DESCRIPTION:END -->
