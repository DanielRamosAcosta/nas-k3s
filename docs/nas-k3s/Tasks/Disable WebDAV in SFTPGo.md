---
title: Disable WebDAV in SFTPGo
status: Done
created_date: '2026-03-09 16:54'
labels:
  - security
  - chore
  - kubernetes
dependencies: []
priority: 3
ordinal: 41000
---

## Description

Deshabilitar completamente WebDAV en SFTPGo, ya que al final se está usando Samba sobre la VPN para acceso a archivos. Eliminar la configuración de WebDAV, puertos y cualquier IngressRoute asociada para reducir superficie de ataque y simplificar el setup.
