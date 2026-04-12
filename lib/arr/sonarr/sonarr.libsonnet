local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('sonarr', replicas=1, containers=[
                  container.new('sonarr', u.image(versions.sonarr.image, versions.sonarr.version)) +
                  container.withPorts([
                    containerPort.new('http', 8989),
                  ]) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('config', '/config'),
                    volumeMount.new('data', '/data'),
                  ]) +
                  u.probes.http('/ping', 8989),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromHostPath('config', '/data/arr/sonarr'),
                  u.volume.fromHostPath('data', '/cold-data/media'),
                ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      PUID: '1000',
      PGID: '100',
      UMASK: '002',
      TZ: 'Atlantic/Canary',
      SONARR__LOG__CONSOLEFORMAT: 'Clef',
    }),
  },
}
