local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'monitoring/immich-exporter/immich-exporter.secrets.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('immich-exporter', replicas=1, containers=[
      container.new('immich-exporter', u.image(versions.immichExporter.image, versions.immichExporter.version)) +
      container.withPorts(containerPort.new('metrics', 3000)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      u.probes.http('/metrics', 3000),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('3000'),

    configEnv: u.configMap.forEnv(self.deployment, {
      IMMICH_HOST: 'http://immich.media.svc.cluster.local:2283',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.immichExporter),
  },
}
