local grafana = import 'monitoring/grafana.libsonnet';
local loki = import 'monitoring/loki.libsonnet';
local nodeExporter = import 'monitoring/node-exporter.libsonnet';
local nutExporter = import 'monitoring/nut-exporter.libsonnet';
local prometheus = import 'monitoring/prometheus.libsonnet';
local promtail = import 'monitoring/promtail.libsonnet';
local smartctlExporter = import 'monitoring/smartctl-exporter.libsonnet';

{
  grafana: grafana.new(),
  loki: loki.new(),
  promtail: promtail.new(),
  prometheus: prometheus.new(),
  nodeExporter: nodeExporter.new(),
  smartctlExporter: smartctlExporter.new(),
  nutExporter: nutExporter.new(),
}
