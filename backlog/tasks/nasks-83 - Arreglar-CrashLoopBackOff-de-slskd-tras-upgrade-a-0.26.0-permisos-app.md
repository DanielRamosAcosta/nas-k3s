---
id: NASKS-83
title: Arreglar CrashLoopBackOff de slskd tras upgrade a 0.26.0 (permisos /app)
status: Done
assignee: []
created_date: '2026-08-07 16:53'
updated_date: '2026-08-07 16:57'
labels: []
dependencies: []
references:
  - 'https://github.com/slskd/slskd/releases/tag/0.26.0'
  - 'https://github.com/slskd/slskd/pull/1709'
modified_files:
  - lib/arr/slskd/slskd.libsonnet
priority: medium
type: bug
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

El upgrade de slskd `0.25.1 → 0.26.0` (PR #151, Renovate) dejó un rollout atascado: el pod nuevo lleva 9 días en CrashLoopBackOff porque el nuevo entrypoint exige que `SLSKD_APP_DIR` (`/app`) sea escribible por el usuario del contenedor (1000:100), pero solo montamos el subdirectorio `/app/data`. Se corrige montando el hostPath entero en `/app`.

## 🎯 Contexto funcional

`slskd` (cliente Soulseek, namespace `arr`) tiene un rollout parado desde hace ~9 días:

- `slskd-68ddf74759` (imagen **0.25.1**) → Running, sirviendo tráfico.
- `slskd-6d485cfc89` (imagen **0.26.0**) → CrashLoopBackOff (2798 reinicios).

El servicio NO está caído (el pod viejo sigue vivo porque el nuevo nunca llega a Ready), pero el clúster arrastra un pod en crash y la versión no ha avanzado. Nadie lo detectó porque no hubo interrupción de servicio.

## ⚙️ Contexto técnico

slskd 0.26.0 (PR upstream #1709) reescribió el entrypoint del contenedor. Al correr con `runAsUser: 1000 / runAsGroup: 100` (modo `--user`), el entrypoint ahora comprueba que `SLSKD_APP_DIR` (por defecto `/app`) sea legible/escribible por ese usuario y **aborta** si no lo es:

```
ERROR: /app is not readable and/or writable by the current user (1000:100); currently owned by root:root (0:0).
To fix: chown -R 1000:100 /path/to/your/mounted/app/directory
```

Nuestra lib (`lib/arr/slskd/slskd.libsonnet`) monta el hostPath `/data/arr/slskd/data` en `/app/data` (solo el subdirectorio). `/app` en sí lo crea el runtime como `root:root`, así que el check falla. Además el entrypoint espera que `/app` entero sea un bind mount. En 0.26.0 el binario vive en `/slskd` (no en `/app`), por lo que montar sobre `/app` es seguro.

**Fix:** montar el hostPath `/data/arr/slskd` en `/app` en lugar de `/data/arr/slskd/data` en `/app/data`. El directorio del NAS ya tiene el layout que espera slskd (`data/` con los .db, todo `1000:100`), por lo que los datos NO se mueven: `/app/data` sigue apuntando a los mismos ficheros. El ConfigMap `slskd.yml` se sigue montando como subPath en `/app/slskd.yml`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 El pod de slskd 0.26.0 arranca y queda en estado Running/Ready (1/1), sin CrashLoopBackOff
- [x] #2 No quedan ReplicaSets antiguos con pods en crash; solo corre la versión 0.26.0
- [x] #3 Los datos persistentes (search.db, events.db, backups, etc.) siguen accesibles sin migración manual
- [x] #4 slskd responde correctamente (health/UI) tras el rollout
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fix en `lib/arr/slskd/slskd.libsonnet`: el volumen `data` (hostPath) pasa de `/data/arr/slskd/data`→`/app/data` a `/data/arr/slskd`→`/app`. Así `/app` es un bind mount owned 1000:100 y el entrypoint de 0.26.0 pasa el check de escritura. El ConfigMap `slskd.yml` se mantiene como subPath en `/app/slskd.yml` (mount anidado). Sin migración de datos: los `.db` ya vivían en `/data/arr/slskd/data`, que ahora es `/app/data` (ruta por defecto de slskd para data).

Desplegado vía GitOps (PR #174, squash merge). Verificado: pod `slskd-679f5674bc-qmh8f` Running 1/1, 0 reinicios, imagen 0.26.0; RS antiguos a 0; log `Backed database /app/data/search.db up to .../backups/...` y `Sharing 57 directories and 406 files` confirman acceso a datos. slskd 0.26.0 corrió además una migración de su DB (con backup previo automático).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rollout de slskd atascado 9 días en CrashLoopBackOff tras el upgrade 0.25.1→0.26.0 (#151). El nuevo entrypoint (upstream PR #1709) exige que `SLSKD_APP_DIR` (`/app`) sea escribible por el usuario no-root del contenedor; montábamos solo `/app/data`, dejando `/app` como root:root. Se soluciona montando el hostPath `/data/arr/slskd` entero en `/app`. Desplegado en PR #174; pod 0.26.0 Running 1/1 sin reinicios y datos intactos.
<!-- SECTION:FINAL_SUMMARY:END -->
