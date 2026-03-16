local u = import '../../utils.libsonnet';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local versions = import '../../versions.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('deluge', replicas=1, containers=[
                   container.new('deluge', u.image(versions.deluge.image, versions.deluge.version)) +
                   container.withPorts([
                     containerPort.new('web', 8112),
                     containerPort.new('daemon', 58846),
                     containerPort.new('peer-tcp', 58946),
                     containerPort.newUDP('peer-udp', 58946),
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
                   u.volume.fromHostPath('config', '/data/arr/deluge'),
                   u.volume.fromHostPath('data', '/cold-data/media'),
                 ]),

    service: k.util.serviceFor(self.statefulSet),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      PUID: '1000',
      PGID: '100',
      UMASK: '002',
      TZ: 'Atlantic/Canary',
      DELUGE_LOGLEVEL: 'info',
    }),
  },
}
