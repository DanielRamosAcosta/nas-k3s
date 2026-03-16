local u = import '../../utils.libsonnet';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local versions = import '../../versions.json';

local secrets = import 'arr/slskd/slskd.secrets.json';
local slskdConfig = import './slskd.config.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('slskd', replicas=1, containers=[
                   container.new('slskd', u.image(versions.slskd.image, versions.slskd.version)) +
                   container.withPorts([
                     containerPort.new('http', 5030),
                     containerPort.new('https', 5031),
                     containerPort.new('slsk', 50300),
                   ]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv) +
                     u.envVars.fromSealedSecret(self.sealed_secret)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('data', '/app/data'),
                     volumeMount.new('music', '/music'),
                     volumeMount.new('downloads', '/downloads'),
                     volumeMount.new('incomplete', '/incomplete'),
                     u.volumeMount.fromFile(self.configFile, '/app'),
                   ]) +
                   container.securityContext.withRunAsUser(1000) +
                   container.securityContext.withRunAsGroup(100),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   u.volume.fromHostPath('data', '/data/arr/slskd/data'),
                   u.volume.fromHostPath('music', '/cold-data/media/music/library/all'),
                   u.volume.fromHostPath('downloads', '/cold-data/media/music/downloads'),
                   u.volume.fromHostPath('incomplete', '/cold-data/media/music/incomplete'),
                   u.volume.fromConfigMap(self.configFile),
                 ]),

    service: k.util.serviceFor(self.statefulSet),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      SLSKD_REMOTE_CONFIGURATION: 'false',
      SLSKD_SHARED_DIR: '/music',
      TZ: 'Atlantic/Canary',
    }),

    sealed_secret: u.sealedSecret.forEnv(self.statefulSet, secrets.slskd),

    configFile: u.configMap.forFile('slskd.yml', std.manifestYamlDoc(u.withoutSchema(slskdConfig))),
  },
}
