---
id: NASKS-29
title: Investigar JPEGs con bloques DCT corruptos en Immich
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
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problema

Immich falla al generar thumbnails para archivos JPEG con bloques DCT corruptos. El error viene de jpegli (la librería JPEG de Google usada por libvips/sharp).

### Error exacto
```
Error: VipsJpeg: ./lib/jpegli/decode_scan.cc:539: Failed to decode DCT block
```

Se encontraron 2 ocurrencias en el rango `2026-03-17T23:36:51Z` a `2026-03-18T01:02:43Z`.

### Assets afectados

| Asset ID | Error detail |
|---|---|
| `627a2b75-9e42-4317-bdda-24377d96432d` | `VipsJpeg: ./lib/jpegli/decode_scan.cc:539: Failed to decode DCT block` |
| `f57a0efa-aa04-4c44-82dd-becbcc68b862` | `VipsJpeg: ./lib/jpegli/decode_scan.cc:539: Failed to decode DCT block` |

Los logs no incluyen rutas de archivo, solo los asset IDs. Para obtener las rutas reales, consultar la base de datos PostgreSQL de Immich:

```sql
SELECT "originalPath", "ownerId"
FROM assets
WHERE id IN (
  '627a2b75-9e42-4317-bdda-24377d96432d',
  'f57a0efa-aa04-4c44-82dd-becbcc68b862'
);
```

### Cómo encontrar estos logs

**Datasource:** Loki (UID: `P8E80F9AEF21F6940`)

```logql
{service_name="immich", level="error"} |= "Failed to decode DCT block"
```

Los logs originales se detectaron en el rango `2026-03-17T23:36:51Z` a `2026-03-18T01:02:43Z`.

### Posibles acciones
- Identificar los archivos concretos a partir de los asset IDs (consultar DB de Immich con la query de arriba)
- Intentar reparar los archivos con `jpegoptim` o `jpegtran`
- Si no se pueden reparar, eliminar o ignorar
<!-- SECTION:DESCRIPTION:END -->
