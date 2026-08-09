local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'monitoring/scraparr/scraparr.secrets.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('scraparr', replicas=1, containers=[
      container.new('scraparr', u.image(versions.scraparr.image, versions.scraparr.version)) +
      container.withPorts(containerPort.new('metrics', 7100)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      u.probes.http('/metrics', 7100),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('7100'),

    configEnv: u.configMap.forEnv(self.deployment, {
      SONARR_URL: 'http://sonarr.arr.svc.cluster.local:8989',
      RADARR_URL: 'http://radarr.arr.svc.cluster.local:7878',
      LIDARR_URL: 'http://lidarr.arr.svc.cluster.local:8686',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.scraparr),
  },
}
