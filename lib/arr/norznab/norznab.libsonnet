local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'arr/norznab/norznab.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('norznab', replicas=1, containers=[
                   container.new('norznab', u.image(versions.norznab.image, versions.norznab.version)) +
                   container.withPorts([
                     containerPort.new('http', 3000),
                   ]) +
                   container.withEnv(
                     u.envVars.fromSealedSecret(self.sealedSecret) +
                     u.envVars.fromConfigMap(self.config)
                   ) +
                   u.probes.tcp(3000),
                 ]) +
                 deployment.spec.strategy.withType('Recreate'),

    service: k.util.serviceFor(self.deployment),

    config: u.configMap.forEnv(self.deployment, {
      DON_TORRENT_BASE_URL: 'https://dontorrent.pink',
      MARCIANO_TORRENT_BASE_URL: 'https://marcianotorrent.net',
      REQUEST_TIMEOUT_MS: '20000',
      HTTP_PROXY: 'http://gluetun.system.svc.cluster.local:8888',
      HTTPS_PROXY: 'http://gluetun.system.svc.cluster.local:8888',
      NO_PROXY: 'localhost,127.0.0.1,.svc.cluster.local',
      NODE_USE_ENV_PROXY: '1',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.norznab),
  },
}
