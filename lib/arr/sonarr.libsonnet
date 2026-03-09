local u = import '../utils.libsonnet';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new(image='ghcr.io/hotio/sonarr', version):: {
    statefulSet: statefulSet.new('sonarr', replicas=1, containers=[
                   container.new('sonarr', u.image(image, version)) +
                   container.withPorts([
                     containerPort.new('http', 8989),
                   ]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('config', '/config'),
                     volumeMount.new('data', '/data'),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   u.volume.fromHostPath('config', '/data/arr/sonarr'),
                   u.volume.fromHostPath('data', '/cold-data/media'),
                 ]),

    service: k.util.serviceFor(self.statefulSet),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      PUID: '1000',
      PGID: '100',
      UMASK: '002',
      TZ: 'Atlantic/Canary',
      SONARR__LOG__CONSOLEFORMAT: 'Clef',
    }),
  },
}
