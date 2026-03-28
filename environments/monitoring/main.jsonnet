local grafana = import 'monitoring/grafana/grafana.libsonnet';
local kubeStateMetrics = import 'monitoring/kube-state-metrics/kube-state-metrics.libsonnet';
local loki = import 'monitoring/loki/loki.libsonnet';
local nodeExporter = import 'monitoring/node-exporter/node-exporter.libsonnet';
local nutExporter = import 'monitoring/nut-exporter/nut-exporter.libsonnet';
local promtail = import 'monitoring/promtail/promtail.libsonnet';
local smartctlExporter = import 'monitoring/smartctl-exporter/smartctl-exporter.libsonnet';
local victoriametrics = import 'monitoring/victoriametrics/victoriametrics.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  grafana: grafana.new(),
  loki: {
    loki: loki.new(),
    promtail: promtail.new(),
  },
  monitoringExporters: {
    nodeExporter: nodeExporter.new(),
    smartctlExporter: smartctlExporter.new(),
    nutExporter: nutExporter.new(),
    kubeStateMetrics: kubeStateMetrics.new(),
  },
  victoriametrics: victoriametrics.new(),
})
