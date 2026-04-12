local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local beetsConfig = import './beets.config.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('beets', replicas=1, containers=[
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
                    u.volumeMount.fromFile(self.configFile, '/config'),
                  ]) +
                  u.probes.http('/', 8337),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromHostPath('data', '/data/beets/data'),
                  u.volume.fromHostPath('music', '/cold-data/media/music/library/all'),
                  u.volume.fromConfigMap(self.configFile),
                ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      PUID: '1000',
      PGID: '100',
      UMASK: '002',
      TZ: 'Atlantic/Canary',
    }),

    configFile: u.configMap.forFile('config.yaml', std.manifestYamlDoc(beetsConfig)),
  },
}
