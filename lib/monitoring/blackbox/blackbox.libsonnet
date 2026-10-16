local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  local configuration = importstr './blackbox.config.yml',

  new():: {
    deployment: deployment.new('blackbox-exporter', replicas=1, containers=[
                  container.new('blackbox-exporter', u.image(versions.blackboxExporter.image, versions.blackboxExporter.version)) +
                  container.withPorts(containerPort.new('http', 9115)) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.configuration, '/etc/blackbox_exporter'),
                  ]) +
                  u.probes.http('/-/healthy', 9115),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.injectFile(self.configuration),
                ]),

    // Sin anotacion prometheus.io/scrape: las sondas se obtienen via un job
    // multi-target en VictoriaMetrics contra /probe, no scrapeando /metrics.
    service: k.util.serviceFor(self.deployment),

    configuration: u.configMap.forFile('config.yml', configuration),
  },
}
