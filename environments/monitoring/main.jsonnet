local grafana = import 'monitoring/grafana/grafana.libsonnet';
local loki = import 'monitoring/loki/loki.libsonnet';
local nodeExporter = import 'monitoring/node-exporter/node-exporter.libsonnet';
local nutExporter = import 'monitoring/nut-exporter/nut-exporter.libsonnet';
local prometheus = import 'monitoring/prometheus/prometheus.libsonnet';
local promtail = import 'monitoring/promtail/promtail.libsonnet';
local smartctlExporter = import 'monitoring/smartctl-exporter/smartctl-exporter.libsonnet';
local u = import 'utils.libsonnet';

{
  grafana: u.labelApp('grafana', grafana.new()),
  loki: u.labelApp('loki', loki.new()),
  promtail: u.labelApp('loki', promtail.new()),
  prometheus: u.labelApp('prometheus', prometheus.new()),
  nodeExporter: u.labelApp('prometheus', nodeExporter.new()),
  smartctlExporter: u.labelApp('prometheus', smartctlExporter.new()),
  nutExporter: u.labelApp('prometheus', nutExporter.new()),
}
