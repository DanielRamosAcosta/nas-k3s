---
id: NASKS-28
title: Investigar JPEGs truncados que fallan en generación de thumbnails en Immich
status: To Do
assignee: []
created_date: '2026-03-18 17:15'
updated_date: '2026-03-18 19:58'
labels:
  - immich
  - media
  - bug
dependencies: []
priority: low
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problema

Immich falla al generar thumbnails para varios archivos JPEG con `premature end of JPEG image`. Esto indica archivos JPEG que están incompletos o fueron cortados durante una copia/transferencia.

### Error exacto
```
Error: VipsJpeg: premature end of JPEG image
```

Se encontraron 4 ocurrencias en una sola ventana de tiempo. Los asset IDs afectados:
- `25370cd4-ee13-415f-bf33-9c481b794e69`
- `85b34f1a-ebfd-48c4-b95c-aa6b3d2330bf`
- `d6ca7de1-5350-4862-8278-7d1210a4c03d`
- `44322ae8-8073-48d3-8721-3896a41cfde5`

### Cómo encontrar estos logs

**Datasource:** Loki (UID: `P8E80F9AEF21F6940`)

```logql
{service_name="immich", level="error"} |= "premature end of JPEG"
```

Los logs originales se detectaron en el rango `2026-03-17T23:36:51Z` a `2026-03-18T01:02:43Z`.

### Posibles acciones
- Identificar los archivos concretos a partir de los asset IDs (consultar la DB de Immich)
- Verificar integridad de los archivos originales en el NAS
- Si los archivos están truncados, eliminarlos o reemplazarlos desde un backup
<!-- SECTION:DESCRIPTION:END -->
