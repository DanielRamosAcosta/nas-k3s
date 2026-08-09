local delugeExporter = import 'monitoring/deluge-exporter/deluge-exporter.libsonnet';
local grafana = import 'monitoring/grafana/grafana.libsonnet';
local immichExporter = import 'monitoring/immich-exporter/immich-exporter.libsonnet';
local kubeStateMetrics = import 'monitoring/kube-state-metrics/kube-state-metrics.libsonnet';
local loki = import 'monitoring/loki/loki.libsonnet';
local mcMonitor = import 'monitoring/mc-monitor/mc-monitor.libsonnet';
local nodeExporter = import 'monitoring/node-exporter/node-exporter.libsonnet';
local nutExporter = import 'monitoring/nut-exporter/nut-exporter.libsonnet';
local promtail = import 'monitoring/promtail/promtail.libsonnet';
local scraparr = import 'monitoring/scraparr/scraparr.libsonnet';
local smartctlExporter = import 'monitoring/smartctl-exporter/smartctl-exporter.libsonnet';
local victoriametrics = import 'monitoring/victoriametrics/victoriametrics.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  grafana: grafana.new(),
  loki: loki.new(),
  promtail: promtail.new(),
  nodeExporter: nodeExporter.new(),
  smartctlExporter: smartctlExporter.new(),
  nutExporter: nutExporter.new(),
  immichExporter: immichExporter.new(),
  scraparr: scraparr.new(),
  mcMonitor: mcMonitor.new(),
  delugeExporter: delugeExporter.new(),
  kubeStateMetrics: kubeStateMetrics.new(),
  victoriametrics: victoriametrics.new(),
})
