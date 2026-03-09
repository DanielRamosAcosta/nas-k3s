local versions = import '../versions.json';
local grafana = import 'monitoring/grafana.libsonnet';
local loki = import 'monitoring/loki.libsonnet';
local nodeExporter = import 'monitoring/node-exporter.libsonnet';
local nutExporter = import 'monitoring/nut-exporter.libsonnet';
local prometheus = import 'monitoring/prometheus.libsonnet';
local promtail = import 'monitoring/promtail.libsonnet';
local smartctlExporter = import 'monitoring/smartctl-exporter.libsonnet';

{
  grafana: grafana.new(
    version=versions.grafana.version
  ),
  loki: loki.new(
    version=versions.loki.version
  ),
  promtail: promtail.new(
    version=versions.promtail.version
  ),
  prometheus: prometheus.new(
    version=versions.prometheus.version
  ),
  nodeExporter: nodeExporter.new(
    version=versions.nodeExporter.version
  ),
  smartctlExporter: smartctlExporter.new(
    version=versions.smartctlExporter.version
  ),
  nutExporter: nutExporter.new(
    version=versions.nutExporter.version
  ),
}
