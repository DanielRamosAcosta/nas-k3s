---
id: NASKS-27
title: Investigar imágenes con headers corruptos en library de Immich
status: To Do
assignee: []
created_date: '2026-03-18 17:15'
updated_date: '2026-03-18 21:27'
labels:
  - immich
  - media
  - bug
dependencies: []
priority: low
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problema

Immich falla al generar thumbnails para 4 archivos `.jpg` con headers corruptos en la library de alex. El job `AssetGenerateThumbnails` lanza `ImproperImageHeader` vía sharp/magickload.

### Assets afectados

| Asset ID | File Path | Owner |
|----------|-----------|-------|
| `ce3aafa6-c9fb-4ec5-9f78-cbb8a1e8a5b0` | `/usr/src/app/upload/library/alex/2018/2018-06-10/P4250316.jpg` | alex |
| `1f045c8b-6658-4c19-b018-ab99cd36d1db` | `/usr/src/app/upload/library/alex/2018/2018-06-10/P4250315.jpg` | alex |
| `9843041a-3750-4178-9817-3c2b9750292e` | `/usr/src/app/upload/library/alex/2018/2018-06-10/P4240245.jpg` | alex |
| `2a79db36-1f76-42aa-b822-2feed03b6462` | `/usr/src/app/upload/library/alex/2018/2018-06-10/P4240260.jpg` | alex |

### Error exacto
```
Error: Input file has corrupt header: magickload: Magick: ImproperImageHeader `.../P4250316.jpg' @ error/tga.c/ReadTGAImage/221 (null)
```

El error en `tga.c/ReadTGAImage` sugiere que sharp/libmagick está interpretando los JPEGs como archivos TGA, lo que indica que los headers están dañados.

### Cómo encontrar estos logs

**Datasource:** Loki (UID: `P8E80F9AEF21F6940`)

```logql
{service_name="immich", level="error"} |= "ImproperImageHeader"
```

Los logs originales se detectaron en el rango `2026-03-17T23:36:51Z` a `2026-03-18T01:02:43Z`.

### Posibles acciones
- Verificar si los archivos originales están realmente corruptos (abrir desde NAS)
- Si están corruptos, eliminarlos de la library o marcarlos como ignorados en Immich
- Si no están corruptos, puede ser un bug de sharp/libmagick con ciertos JPEGs de cámara Olympus (P4250316 parece ser de una Olympus)
<!-- SECTION:DESCRIPTION:END -->
