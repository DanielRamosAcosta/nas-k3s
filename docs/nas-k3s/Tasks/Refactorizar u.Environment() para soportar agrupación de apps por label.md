---
title: Refactorizar u.Environment() para soportar agrupación de apps por label
status: Draft
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
