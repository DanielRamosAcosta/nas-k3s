local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local beetsConfig = import './beets.config.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('beets', replicas=1, containers=[
                   container.new('beets', u.image(versions.beets.image, versions.beets.version)) +
                   container.withPorts([
                     containerPort.new('http', 8337),
                   ]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('data', '/data'),
                     volumeMount.new('music', '/music'),
                     volumeMount.new('downloads', '/downloads'),
                     u.volumeMount.fromFile(self.configFile, '/config'),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   u.volume.fromHostPath('data', '/data/beets/data'),
                   u.volume.fromHostPath('music', '/cold-data/media/music/library/all'),
                   u.volume.fromHostPath('downloads', '/cold-data/media/music/downloads'),
                   u.volume.fromConfigMap(self.configFile),
                 ]),

    service: k.util.serviceFor(self.statefulSet),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      PUID: '1000',
      PGID: '100',
      TZ: 'Atlantic/Canary',
    }),

    configFile: u.configMap.forFile('config.yaml', std.manifestYamlDoc(beetsConfig)),
  },
}
