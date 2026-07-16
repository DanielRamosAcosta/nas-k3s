---
name: postgres-create-backup
description: Crear un backup lógico ad-hoc de todas las BBDD de Postgres, p. ej. antes de un cambio de riesgo (upgrade mayor de un servicio). Úsala cuando el usuario quiera forzar un backup inmediato de la BBDD antes de tocar algo.
---

# /postgres-create-backup

Lee y sigue la guía **«Postgres — crear un backup ad-hoc»** de `backlog/docs` (doc-6):

```
mcp__backlog__document_view(id="doc-6")
```

Sigue sus pasos tal cual (disparar el CronJob `postgres-logical-dump` a mano y verificar el dump). No dupliques aquí el procedimiento: la doc es la fuente de verdad.
