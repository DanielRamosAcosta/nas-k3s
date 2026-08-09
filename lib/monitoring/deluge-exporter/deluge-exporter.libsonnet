local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'monitoring/deluge-exporter/deluge-exporter.secrets.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('deluge-exporter', replicas=1, containers=[
      container.new('deluge-exporter', u.image(versions.delugeExporter.image, versions.delugeExporter.version)) +
      container.withPorts(containerPort.new('metrics', 8011)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      u.probes.http('/', 8011),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('8011'),

    configEnv: u.configMap.forEnv(self.deployment, {
      DELUGE_URL: 'http://deluge.arr.svc.cluster.local:8112',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.delugeExporter),
  },
}
