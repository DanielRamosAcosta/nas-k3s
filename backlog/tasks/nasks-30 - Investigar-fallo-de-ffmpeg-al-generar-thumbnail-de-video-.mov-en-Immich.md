---
id: NASKS-30
title: Investigar fallo de ffmpeg al generar thumbnail de video .mov en Immich
status: Done
assignee: []
created_date: '2026-03-18 17:15'
updated_date: '2026-03-19 07:48'
labels:
  - immich
  - media
  - bug
dependencies: []
priority: low
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problema

Immich falla al generar thumbnail para un video `.mov` de iMovie (2011). ffmpeg no puede codificar el frame extraído como MJPEG porque el video usa YUV non full-range, y el encoder mjpeg lo rechaza sin `strict_std_compliance` relajado.

### Archivo afectado
- `/usr/src/app/upload/library/alex/2011/2011-11-18/Cache-30.mov`
- Asset ID: `98d5489e-6adf-48c8-82fb-003aad1dbc27`
- Formato: Apple Intermediate Codec (AIC), 1280x720, yuv420p
- Duración: 8:28

### Error exacto
```
[mjpeg @ ...] Non full-range YUV is non-standard, set strict_std_compliance to at most unofficial to use it.
Error while opening encoder - maybe incorrect parameters such as bit_rate, rate, width or height.
```

ffmpeg sale con código 234 (`Conversion failed!`).

### Cómo encontrar estos logs

**Datasource:** Loki (UID: `P8E80F9AEF21F6940`)

```logql
{service_name="immich", level="error"} |= "Conversion failed"
```

O para ver el log completo de ffmpeg:

```logql
{service_name="immich", level="error"} |= "Non full-range YUV"
```

Los logs originales se detectaron en el rango `2026-03-17T23:36:51Z` a `2026-03-18T01:02:43Z`.

### Posibles acciones
- Este es un bug conocido de ffmpeg con ciertos videos Apple Intermediate Codec — el thumbnail filter extrae un frame con range limitado y mjpeg lo rechaza
- Verificar si hay una versión más reciente de Immich que maneje esto (puede que ya añadan `-strict unofficial` o conviertan el rango)
- Alternativamente, re-encodar el video manualmente para que sea compatible
<!-- SECTION:DESCRIPTION:END -->
