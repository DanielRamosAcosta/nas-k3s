---
id: NASKS-59
title: Activar backups automáticos de VictoriaMetrics con vmbackupmanager
status: To Do
assignee: []
created_date: '2026-04-29 06:54'
updated_date: '2026-06-19 16:56'
labels:
  - monitoring
  - victoriametrics
  - backup
dependencies: []
priority: medium
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Aprovechar que VictoriaMetrics corre en versión Enterprise (license activado en c0d827e+) para configurar backups incrementales automáticos del directorio `/data/victoriametrics/data` mediante `vmbackupmanager`.

## Contexto

- VM corre como single-node StatefulSet en `monitoring/victoriametrics-0`, imagen `victoriametrics/victoria-metrics:v1.140.0-enterprise`.
- Datos en hostPath `/data/victoriametrics/data` (SSD del NAS).
- Sin backup actual → un fallo del disco/NAS pierde todo el histórico.
- `vmbackupmanager` es un binario aparte que se ejecuta como sidecar o pod independiente, llama al endpoint `/snapshot/create` de VM y sube los snapshots incrementales al backend elegido con rotación (hourly/daily/weekly/monthly).

## Backends soportados por vmbackupmanager

- `gs://` (GCS)
- `s3://` (S3 + cualquier compatible: Backblaze B2, Cloudflare R2, MinIO, Hetzner Object Storage, Wasabi…)
- `azblob://` (Azure Blob)
- `fs://` (filesystem local — útil solo contra borrado accidental, no contra fallo de disco)

**Decidir el backend antes de empezar.** Recomendaciones para homelab:
- Backblaze B2 (~$6/TB/mes, sin egress hasta 3× lo almacenado)
- Cloudflare R2 (sin egress, $15/TB/mes)
- Hetzner Object Storage (si ya hay cuenta)

## Aspectos a resolver

1. Elegir backend + bucket + región.
2. Cifrar credenciales (access key/secret) como SealedSecret en namespace `monitoring`.
3. Decidir layout: sidecar dentro del Pod de `victoriametrics` (comparte hostPath) vs Deployment aparte que monte el mismo hostPath.
4. Configurar política de retención: hourly/daily/weekly/monthly (`-keepLastHourly`, `-keepLastDaily`, etc.).
5. Métricas de vmbackupmanager → scrape para alertar si el backup falla.
6. Probar restore en seco (montar snapshot en directorio temporal y validar) — sin restore probado el backup no cuenta.

## Referencias

- https://docs.victoriametrics.com/victoriametrics/vmbackupmanager/
- https://docs.victoriametrics.com/victoriametrics/vmbackup/
- `lib/monitoring/victoriametrics/victoriametrics.libsonnet` (donde añadir el sidecar/sibling)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Backend de backup elegido y documentado en la descripción de la tarea (S3/GCS/Azure/B2/R2/etc.) con bucket creado
- [ ] #2 Credenciales del backend cifradas como SealedSecret en namespace monitoring
- [ ] #3 vmbackupmanager desplegado vía Tanka (sidecar en el StatefulSet o Deployment aparte que monte el hostPath de VM), con `-licenseFile` apuntando al mismo SealedSecret de license
- [ ] #4 Política de retención configurada: al menos hourly + daily + weekly definidos via flags `-keepLast*`
- [ ] #5 Primer backup ejecutado correctamente y verificado en el bucket destino
- [ ] #6 Restore probado en seco: snapshot bajado a un directorio temporal y validado que arranca un VM contra él (no requiere restore en producción)
- [ ] #7 Métricas de vmbackupmanager scrapeadas por VM (alerta básica si `vm_backups_failed_total` incrementa)
- [ ] #8 README/CLAUDE.md o doc en repo con el procedimiento de restore documentado
<!-- AC:END -->
