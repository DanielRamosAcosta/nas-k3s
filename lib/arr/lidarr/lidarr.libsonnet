local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('lidarr', replicas=1, containers=[
                   container.new('lidarr', u.image(versions.lidarr.image, versions.lidarr.version)) +
                   container.withPorts([
                     containerPort.new('http', 8686),
                   ]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('config', '/config'),
                     volumeMount.new('data', '/data'),
                   ]) +
                   u.probes.http('/ping', 8686),
                 ]) +
                 deployment.spec.template.spec.withVolumes([
                   u.volume.fromHostPath('config', '/data/arr/lidarr'),
                   u.volume.fromHostPath('data', '/cold-data/media'),
                 ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      PUID: '1000',
      PGID: '100',
      UMASK: '002',
      TZ: 'Atlantic/Canary',
      LIDARR__LOG__CONSOLEFORMAT: 'Clef',
    }),
  },
}
