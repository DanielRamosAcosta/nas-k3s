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
    image=versions.grafana.image,
    version=versions.grafana.version,
  ),
  loki: loki.new(
    image=versions.loki.image,
    version=versions.loki.version,
  ),
  promtail: promtail.new(
    image=versions.promtail.image,
    version=versions.promtail.version,
  ),
  prometheus: prometheus.new(
    image=versions.prometheus.image,
    version=versions.prometheus.version,
  ),
  nodeExporter: nodeExporter.new(
    image=versions.nodeExporter.image,
    version=versions.nodeExporter.version,
  ),
  smartctlExporter: smartctlExporter.new(
    image=versions.smartctlExporter.image,
    version=versions.smartctlExporter.version,
  ),
  nutExporter: nutExporter.new(
    image=versions.nutExporter.image,
    version=versions.nutExporter.version,
  ),
}
