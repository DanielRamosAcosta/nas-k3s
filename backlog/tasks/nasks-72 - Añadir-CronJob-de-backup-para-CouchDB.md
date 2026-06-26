---
id: NASKS-72
title: Añadir CronJob de backup para CouchDB
status: To Do
assignee: []
created_date: '2026-06-25 22:53'
labels: []
dependencies:
  - NASKS-71
references:
  - lib/databases/postgres
  - lib/databases/couchdb
priority: low
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Añadir un CronJob que haga un dump periódico de la(s) database(s) de CouchDB a `/cold-data`, como red de seguridad más allá de las réplicas de los dispositivos LiveSync.

## 🎯 Contexto funcional

CouchDB (desplegado en NASKS-71) sirve como backend de Obsidian LiveSync, que replica la base de datos en cada dispositivo, así que existe una recuperación natural ("rebuild from this device"). Por eso el despliegue inicial se hizo **sin backup dedicado**.

Sin embargo, un backup dedicado protege de dos escenarios:
1. Una **corrupción que se propague a todos los dispositivos** antes de detectarla.
2. Que en el futuro se alojen en este CouchDB **otras apps cuyos datos NO estén replicados** en dispositivos — ahí el backup deja de ser opcional.

## ⚙️ Contexto técnico

- Replicar el patrón de backup ya existente en Postgres (`backup.sh` + `cleanup.sh`): un CronJob que vuelca periódicamente las databases de CouchDB a `/cold-data` (HDD), con rotación/limpieza de backups antiguos.
- Vivirá en el módulo `lib/databases/couchdb/`.
- El dump de CouchDB puede hacerse vía la API HTTP (p. ej. `couchbackup`/`couchdb-dump` o un simple `curl` a `_all_docs?include_docs=true` / replicación a fichero), autenticándose con las credenciales admin desde el SealedSecret (scope strict, namespace `databases`).
- Prioridad baja: no bloquea el despliegue; las réplicas de los dispositivos cubren el caso común.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CronJob de backup en el módulo lib/databases/couchdb/ que vuelca la(s) database(s) de CouchDB a /cold-data de forma periódica
- [ ] #2 Limpieza/rotación de backups antiguos (estilo cleanup.sh de Postgres)
- [ ] #3 Backup verificado: un dump se puede restaurar correctamente en una database de CouchDB
<!-- AC:END -->
