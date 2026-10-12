---
title: Refactorizar u.Environment() para soportar agrupación de apps por label
status: Done
created_date: '2026-03-28 08:00'
labels:
  - refactor
  - dx
dependencies: []
references:
  - lib/utils.libsonnet
  - environments/monitoring/main.jsonnet
priority: 3
---

## Description

Actualmente cada environment repite `u.labelApp('nombre', app.new())` manualmente. Buscar una interfaz mejor para `u.Environment()` que permita agrupar apps bajo un mismo label ArgoCD de forma declarativa, algo como:

```jsonnet
u.Environment({
  grafana: grafana.new(),
  loki: {
    loki: loki.new(),
    promtail: promtail.new(),
  },
  exporters: {
    nodeExporter: nodeExporter.new(),
    kubeStateMetrics: kubeStateMetrics.new(),
  },
})
```

Donde las claves de primer nivel se convierten en el label `app` de ArgoCD, y los objetos anidados agrupan múltiples componentes bajo el mismo label.

## Implementation Notes

**`u.Environment()` / `labelApp` ya soportaban el anidamiento.** `core.labelApp` (`lib/utils/core.libsonnet`) ya recursa en objetos sin `metadata` y estampa el label `app` en todos los recursos a cualquier profundidad. Lo único roto era el descubrimiento de apps en ArgoCD.

**Fix único:** `discoverApps` en `lib/utils/argocd.libsonnet` miraba solo dos niveles (`env.resources[key][rkey].metadata`). Reescrito como deep-walk que para en el primer objeto con `metadata` (el recurso) y lee su label `app` de nivel superior. ~10 líneas, un solo sitio.

**Agrupaciones aplicadas:**

| Grupo (label/app) | Componentes | Environment |
|---|---|---|
| `loki` | loki + promtail | monitoring |
| `exporters` | node, smartctl, nut, immich, scraparr, mc-monitor, deluge-exporter, kube-state-metrics | monitoring |
| `minecraft` | minecraft + mc-router + minecraft-backup + squaremap | games |
| `matrix` | synapse + mautrix-whatsapp | communications |

Nombrar el grupo igual que el componente principal (`loki`, `minecraft`) preserva esa Application; solo migran los satélites. `matrix` es nombre nuevo → tanto `synapse` como `mautrix-whatsapp` se recrean.

**Comportamiento de transición (una vez, al desplegar):** al renombrar el label, el app-of-apps borra las Applications antiguas (`promtail`, `node-exporter`, `squaremap`, `minecraft-backup`, `mc-router`, `synapse`, `mautrix-whatsapp`, etc.). Con el finalizer + `prune: true`, borrar esas Applications hace prune de sus recursos → los pods afectados se borran y se recrean bajo la nueva Application. Datos en hostPath sobreviven; es un blip de downtime en esos servicios. StatefulSets (Synapse) sufren un reinicio breve, sin pérdida de datos.

Validado: los 10 environments compilan; labels resultantes = `grafana`, `victoriametrics`, `loki`, `exporters` (monitoring), `minecraft` (games), `matrix` (communications).
