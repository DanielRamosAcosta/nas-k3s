local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/navidrome/navidrome.secrets.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local service = k.core.v1.service,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('navidrome', replicas=1, containers=[
                   container.new('navidrome', u.image(versions.navidrome.image, versions.navidrome.version)) +
                   container.withPorts(
                     [containerPort.new('server', 4533)]
                   ) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv) +
                     u.envVars.fromSealedSecret(self.sealed_secret)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('library', '/library', true),
                     volumeMount.new('data', '/data'),
                   ]) +
                   u.probes.http('/ping', 4533),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   volume.fromHostPath('library', '/cold-data/media/music/library'),
                   volume.fromHostPath('data', '/data/navidrome/data'),
                 ]),

    service: k.util.serviceFor(self.statefulSet) + u.prometheus(port='8081'),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      ND_BASEURL: 'https://music.danielramos.me',
    }),

    sealed_secret: u.sealedSecret.forEnv(self.statefulSet, secrets.navidrome),

    ingressRoute: u.ingressRoute.from(self.service, 'music.danielramos.me'),
  },
}
