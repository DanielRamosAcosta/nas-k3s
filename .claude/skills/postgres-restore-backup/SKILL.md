---
name: postgres-restore-backup
description: Restaurar una sola BBDD de Postgres desde su dump lógico (runbook por etiqueta app=<db>), sin tocar el resto del clúster. Úsala cuando el usuario quiera restaurar/recuperar la BBDD de un servicio (p. ej. immich tras un upgrade que corrompió su esquema).
---

# /postgres-restore-backup

Lee y sigue la guía **«Postgres — restaurar desde un backup»** de `backlog/docs` (doc-7):

```
mcp__backlog__document_view(id="doc-7")
```

Sigue su runbook tal cual (parar la app por `app=<db>`, disparar `restore-<db>-<latest|YYYYMMDD>` desde el CronJob `postgres-restore`, re-arrancar; incluye la alternativa slate-limpio y el caveat de colación `C`). No dupliques aquí el procedimiento: la doc es la fuente de verdad.
