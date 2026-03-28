---
id: DRAFT-2
title: Configurar downsampling en VictoriaMetrics (requiere licencia Enterprise)
status: Draft
assignee: []
created_date: '2026-03-27 23:25'
labels:
  - monitoring
  - victoriametrics
  - blocked
dependencies:
  - NASKS-45
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Activar downsampling nativo en VictoriaMetrics para reducir la resolución de métricas antiguas progresivamente, controlando el crecimiento de disco a largo plazo.

**Bloqueado** hasta recibir respuesta de VictoriaMetrics sobre licencia Enterprise gratuita para homelab (email enviado el 2026-03-28 via formulario de contacto).

### Contexto

- El downsampling (`-downsampling.period`) es una feature exclusiva de VictoriaMetrics Enterprise
- Se solicitó una licencia personal/homelab gratuita basándose en el precedente del [issue #5278](https://github.com/VictoriaMetrics/VictoriaMetrics/issues/5278)
- Sin downsampling, VM OSS funciona igualmente con ~4 GB/año a raw 30s (~40 GB en 10 años), que es aceptable

### Configuración deseada

```
-downsampling.period=30d:5m,180d:1h
```

- 0–30 días: resolución original (30s)
- 30–180 días: downsampling a 5 minutos
- 180+ días: downsampling a 1 hora

### Estimación de ahorro con downsampling (~10.000 series)

| Periodo | Sin downsampling | Con downsampling |
|---|---|---|
| 1 año | ~4 GB | ~700 MB |
| 5 años | ~20 GB | ~1 GB |
| 10 años | ~40 GB | ~1.5 GB |

### Alternativas si no obtenemos licencia

1. Vivir sin downsampling (~4 GB/año es aceptable en el NAS)
2. Recording rules manuales para pre-agregar métricas clave
3. Thanos Compactor (complejo, 4-5 componentes extra)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Licencia Enterprise obtenida (gratuita para homelab)
- [ ] #2 Flag `-downsampling.period=30d:5m,180d:1h` configurado y verificado en logs de arranque
- [ ] #3 Verificar que datos >30 días se downsamplean correctamente
<!-- AC:END -->
